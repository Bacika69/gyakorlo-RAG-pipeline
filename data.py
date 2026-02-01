#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
RAG-Assistant – magyar nyelvű kérdés-válasz rendszer Ollama-LLM-mel,
Sentence-Transformers embeddinggel és PostgreSQL + pgvector tárolóval.

Futtatás:
    python data.py init
    python data.py query
    python data.py query "Kérdés"

Előfeltételek (pip):
    pip install psycopg2-binary pgvector sentence-transformers tiktoken requests numpy
"""

import argparse
import json
import logging
import os
import re
import sys
from dataclasses import dataclass
from typing import List, Tuple, Any, Optional, Dict

import numpy as np
import psycopg2
import psycopg2.extras
import requests
import tiktoken
from sentence_transformers import SentenceTransformer

from pgvector.psycopg2 import register_vector



# ----------------------------------------------------------------------
# Konfiguráció
# ----------------------------------------------------------------------
@dataclass
class Config:
    # PostgreSQL
    pg_dsn: str = os.getenv(
        "PG_DSN",
        "dbname=ai_sql user=postgres password=postgres host=127.0.0.1 port=15432",
    )

    # Embedding modell
    embed_model: str = os.getenv(
        "EMBED_MODEL",
        "sentence-transformers/all-MiniLM-L6-v2",
    )

    # Ollama
    ollama_generate_endpoint: str = os.getenv(
        "OLLAMA_ENDPOINT",
        "http://localhost:11434/api/generate",
    )
    ollama_chat_endpoint: str = os.getenv(
        "OLLAMA_CHAT_ENDPOINT",
        "http://localhost:11434/api/chat",
    )
    ollama_model: str = os.getenv("OLLAMA_MODEL", "llama3.2:3b")



    # Chunk / retrieval
    max_tokens: int = int(os.getenv("MAX_TOKENS", "300"))
    top_k: int = int(os.getenv("TOP_K", "12"))
    candidate_k: int = int(os.getenv("CANDIDATE_K", "80"))   # első körös merítés
    top_tickets: int = int(os.getenv("TOP_TICKETS", "2"))    # hány ticketet engedünk a kontextusba

    # Prompt budget
    model_max_context: int = int(os.getenv("MODEL_MAX_TOKENS", "4096"))
    reserve_for_answer: int = int(os.getenv("RESERVE_FOR_ANSWER", "350"))

    # Embedding batch
    batch_size: int = int(os.getenv("BATCH_SIZE", "256"))

    # Futtatás
    debug: bool = False
    no_stream: bool = False


# ----------------------------------------------------------------------
# Logging
# ----------------------------------------------------------------------
def configure_logging(debug: bool) -> None:
    logging.basicConfig(
        level=logging.DEBUG if debug else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=[logging.StreamHandler(sys.stderr)],
    )


log = logging.getLogger(__name__)


# ----------------------------------------------------------------------
# Tokenizálás
# ----------------------------------------------------------------------
ENCODER = tiktoken.get_encoding("cl100k_base")


def token_len(text: str) -> int:
    return len(ENCODER.encode(text))


def pack_chunks_by_token_budget(
    header: str,
    chunks: List[str],
    model_max_context: int,
    reserve_for_answer: int,
) -> str:
    """
    Összepakolja a contextet token budgetdel. Meghagy tartalékot a válasznak.
    """
    sep = "\n\n---\n\n"
    budget = model_max_context - token_len(header) - reserve_for_answer
    if budget <= 0:
        # minimális fallback
        return "\n\n".join(chunks[:1])

    out: List[str] = []
    used = 0
    sep_tok = token_len(sep)

    for c in chunks:
        c_tok = token_len(c)
        extra = c_tok + (sep_tok if out else 0)
        if used + extra <= budget:
            out.append(c)
            used += extra
        else:
            break

    return sep.join(out)


# ----------------------------------------------------------------------
# Szöveg feldolgozás
# ----------------------------------------------------------------------
def split_into_paragraphs(text: str) -> List[str]:
    return [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]


def split_into_sentences(paragraph: str) -> List[str]:
    paragraph = re.sub(r"\s+", " ", paragraph.strip())
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", paragraph) if s.strip()]


# ----------------------------------------------------------------------
# Topic detektálás
# ----------------------------------------------------------------------
TOPIC_MAP = {
    "Jegy – Belépési problémák": ["belépni", "jelszó", "fiók", "login", "bejelentkezés"],
    "Jegy – Számlázás": ["számla", "számlázás", "díj", "billing", "invoice"],
    "Jegy – Teljesítmény": ["lassú", "betöltés", "teljesítmény", "performance"],
    "Ügyfél": ["ügyfél", "customer"],
    "Support": ["support", "ügynök", "agent"],
}
DEFAULT_LABEL = "[Általános]"
SPECIAL_KEYWORDS = {kw for keys in TOPIC_MAP.values() for kw in keys}


def detect_topic_label(text: str) -> str:
    low = text.lower()
    for label, keys in TOPIC_MAP.items():
        if any(k in low for k in keys):
            return f"[{label}]"
    return DEFAULT_LABEL


# ----------------------------------------------------------------------
# Chunkolás
# ----------------------------------------------------------------------
def _chunk_sentences(sentences: List[str], max_tokens: int) -> List[str]:
    overlap = max(10, int(max_tokens * 0.15))
    chunks: List[str] = []
    cur: List[str] = []
    cur_len = 0

    for s in sentences:
        s_len = token_len(s)

        # ha egyetlen mondat túl hosszú, önálló chunk
        if s_len > max_tokens:
            if cur:
                chunks.append(" ".join(cur))
                cur, cur_len = [], 0
            chunks.append(s)
            continue

        if cur_len + s_len <= max_tokens:
            cur.append(s)
            cur_len += s_len
        else:
            chunks.append(" ".join(cur))
            cur = cur[-overlap:] + [s]
            cur_len = sum(token_len(x) for x in cur)

    if cur:
        chunks.append(" ".join(cur))

    return chunks


def hybrid_chunk(text: str, max_tokens: int) -> List[str]:
    chunks: List[str] = []
    for para in split_into_paragraphs(text):
        low = para.lower()

        # ha van "speciális" kulcsszó, hagyjuk egyben a paragrafust
        if any(k in low for k in SPECIAL_KEYWORDS):
            chunks.append(f"{detect_topic_label(para)} {para}")
            continue

        # ha belefér tokenben, egyben
        if token_len(para) <= max_tokens:
            chunks.append(f"{detect_topic_label(para)} {para}")
            continue

        # különben mondat sliding
        for sc in _chunk_sentences(split_into_sentences(para), max_tokens):
            chunks.append(f"{detect_topic_label(sc)} {sc}")
    print(chunks)
    return chunks


# ----------------------------------------------------------------------
# Embedding
# ----------------------------------------------------------------------
def load_embedder(model_name: str) -> SentenceTransformer:
    try:
        import torch
        device = "cuda" if torch.cuda.is_available() else "cpu"
    except Exception:
        device = "cpu"
    log.info("Embedding modell: %s (%s)", model_name, device)
    return SentenceTransformer(model_name, device=device)


def embed_texts(embedder: SentenceTransformer, texts: List[str], batch_size: int) -> np.ndarray:
    embs = embedder.encode(
        texts,
        batch_size=batch_size,
        normalize_embeddings=True,
        show_progress_bar=False,
    )
    return np.asarray(embs, dtype=np.float32)


# ----------------------------------------------------------------------
# PostgreSQL
# ----------------------------------------------------------------------
def get_connection(dsn: str):
    conn = psycopg2.connect(dsn)
    register_vector(conn)
    return conn


SCHEMA_SQL = """
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS rag_chunks (
    id BIGSERIAL PRIMARY KEY,
    source_table TEXT NOT NULL,
    source_id BIGINT,
    content TEXT NOT NULL,
    embedding vector(384) NOT NULL
);

CREATE INDEX IF NOT EXISTS rag_chunks_embedding_idx
ON rag_chunks USING ivfflat (embedding vector_l2_ops)
WITH (lists = 100);
"""


def init_db(conn) -> None:
    with conn.cursor() as cur:
        cur.execute(SCHEMA_SQL)
    conn.commit()
    log.info("DB schema rendben (rag_chunks + index).")


# ----------------------------------------------------------------------
# Betöltés (tickets + users + messages)
# ----------------------------------------------------------------------
def load_conversations(conn) -> List[Tuple[int, str]]:
    """
    Ticket metaadatok + üzenetváltások összefűzve, ticketenként 1 dokumentum.
    """
    with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
        cur.execute(
            """
            SELECT
                t.id AS ticket_id,
                t.title AS ticket_title,
                u.name AS user_name,
                u.email AS user_email,
                t.status,
                t.priority,
                t.category,
                t.created_at,
                t.closed_at,
                STRING_AGG(
                    '[' || m.sender_type || '] ' || m.sender_name || ': ' || m.body,
                    E'\n'
                    ORDER BY m.created_at
                ) AS conversation
            FROM tickets t
            JOIN users u ON u.id = t.user_id
            LEFT JOIN messages m ON m.ticket_id = t.id
            GROUP BY
                t.id, t.title, u.name, u.email,
                t.status, t.priority, t.category,
                t.created_at, t.closed_at
            ORDER BY t.id;
            """
        )
        rows = cur.fetchall()

    if not rows:
        log.error("Az adatbázisban nincs egyetlen jegy sem.")
        sys.exit(1)

    docs: List[Tuple[int, str]] = []
    for r in rows:
        full_text = (
            f"Jegy ID: {r['ticket_id']}\n"
            f"Cím: {r['ticket_title']}\n"
            f"Ügyfél: {r['user_name']} ({r['user_email']})\n"
            f"Státusz: {r['status']}, Prioritás: {r['priority']}, Kategória: {r['category']}\n"
            f"Létrehozva: {r['created_at']}, Lezárva: {r['closed_at']}\n\n"
            f"Beszélgetés:\n{r['conversation'] or ''}"
        )
        docs.append((int(r["ticket_id"]), full_text))

    log.info("Betöltve %d jegy teljes beszélgetéssel.", len(docs))
    return docs


# ----------------------------------------------------------------------
# Indexelés
# ----------------------------------------------------------------------
def index_documents(conn, docs: List[Tuple[int, str]], embedder: SentenceTransformer, cfg: Config) -> None:
    log.info("Chunk-olás megkezdése (%d dokumentum)...", len(docs))

    all_chunks: List[Tuple[int, str]] = []
    for ticket_id, doc_text in docs:
        chunks = hybrid_chunk(doc_text, max_tokens=cfg.max_tokens)
        for ch in chunks:
            all_chunks.append((ticket_id, ch))

    if not all_chunks:
        log.error("Nem keletkezett egyetlen chunk sem.")
        sys.exit(1)

    texts = [c[1] for c in all_chunks]
    log.info("Embedding számítás (%d chunk)...", len(texts))
    embeddings = embed_texts(embedder, texts, cfg.batch_size)

    with conn.cursor() as cur:
        cur.execute("TRUNCATE rag_chunks;")
        psycopg2.extras.execute_values(
            cur,
            """
            INSERT INTO rag_chunks (source_table, source_id, content, embedding)
            VALUES %s
            """,
            [
                ("tickets", src_id, content, emb.tolist())
                for (src_id, content), emb in zip(all_chunks, embeddings)
            ],
            page_size=500,
        )
    conn.commit()

    # ivfflat index frissítéséhez hasznos
    with conn.cursor() as cur:
        cur.execute("ANALYZE rag_chunks;")
    conn.commit()

    log.info("Indexelés kész. Chunkok: %d", len(all_chunks))


# ----------------------------------------------------------------------
# Lekérdezés: 1. lépés – legjobb ticketek kiválasztása
# ----------------------------------------------------------------------
def retrieve_top_ticket_ids(
    conn,
    query: str,
    embedder: SentenceTransformer,
    candidate_k: int,
    top_tickets: int,
) -> Tuple[List[int], List[float]]:

    # Query embedding
    q_emb = embedder.encode([query], normalize_embeddings=True, show_progress_bar=False)[0].tolist()

    # Itt volt nálad a HIBA: hiányzott a SQL lekérdezés
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT
                1.0 / (1.0 + (embedding <-> %s::vector)) AS score,
                source_id
            FROM rag_chunks
            ORDER BY embedding <-> %s::vector
            LIMIT %s;
            """,
            (q_emb, q_emb, candidate_k),
        )
        rows = cur.fetchall()

    # Ticketenként összegezzük a score-okat
    agg: Dict[int, float] = {}
    for score, sid in rows:
        if sid is None:
            continue
        sid_int = int(sid)
        agg[sid_int] = agg.get(sid_int, 0.0) + float(score)

    # Legjobb ticketek kiválasztása
    ticket_ids = [
        sid for sid, _ in
        sorted(agg.items(), key=lambda kv: kv[1], reverse=True)[:top_tickets]
    ]

    return ticket_ids, q_emb


# ----------------------------------------------------------------------
# Lekérdezés: 2. lépés – chunkok lekérése adott ticketen belül
# ----------------------------------------------------------------------
def retrieve_chunks_for_ticket(
    conn,
    q_emb: List[float],
    ticket_id: int,
    top_k: int,
) -> List[Tuple[float, str]]:

    # Itt volt nálad a HIBA: Vector(q_emb) → TILOS
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT
                1.0 / (1.0 + (embedding <-> %s::vector)) AS score,
                content
            FROM rag_chunks
            WHERE source_id = %s
            ORDER BY embedding <-> %s::vector
            LIMIT %s;
            """,
            (q_emb, ticket_id, q_emb, top_k),
        )
        rows = cur.fetchall()

    rows.sort(key=lambda r: float(r[0]), reverse=True)
    return [(float(score), content) for score, content in rows]



def build_context_for_tickets(
    conn,
    q_emb: List[float],
    ticket_ids: List[int],
    top_k: int,
    cfg: Config,
) -> str:
    blocks: List[str] = []
    for tid in ticket_ids:
        chunks_scored = retrieve_chunks_for_ticket(conn, q_emb, tid, top_k=top_k)
        if not chunks_scored:
            continue

        chunk_texts = [c for _, c in chunks_scored]
        block = f"[TICKET {tid}]\n" + "\n\n---\n\n".join(chunk_texts)
        blocks.append(block)

    if not blocks:
        return ""

    # token budget szerint összepakoljuk a végső contextet
    header = "KONTEKSTUS:\n"
    combined = "\n\n====================\n\n".join(blocks)
    if token_len(header + combined) <= cfg.model_max_context - cfg.reserve_for_answer:
        return combined

    # ha túl hosszú, blokk szinten vágunk
    final_parts: List[str] = []
    for b in blocks:
        if not final_parts:
            candidate = b
        else:
            candidate = "\n\n====================\n\n".join(final_parts + [b])

        if token_len(header + candidate) <= cfg.model_max_context - cfg.reserve_for_answer:
            final_parts.append(b)
        else:
            break

    # ha még így is túl hosszú (ritka), akkor chunk szintű vágás
    if not final_parts:
        return pack_chunks_by_token_budget(header, [blocks[0]], cfg.model_max_context, cfg.reserve_for_answer)

    return "\n\n====================\n\n".join(final_parts)


# ----------------------------------------------------------------------
# Prompt + Ollama chat
# ----------------------------------------------------------------------
SYSTEM_PROMPT = """Feladat: válaszolj magyarul a kérdésre kizárólag a KONTEKSTUS alapján.

Szabályok:
- Ne magyarázd a szabályokat, ne írj meta szöveget.
- Ha a válasz nincs a kontextusban: írd pontosan: Nem szerepel a kontextusban.
- A válasz 2-5 mondat.
- Tegyél bele 1 szó szerinti idézetet a kontextusból.

Kimenet formátum:
Válasz: <itt a válasz>
Idézet: "<szó szerinti idézet>"
"""



def build_user_prompt(question: str, context: str) -> str:
    return f"""KONTEKSTUS:
{context}

KÉRDÉS: {question}
""".strip()



def ollama_chat(system: str, user: str, cfg: Config) -> str:
    payload = {
        "model": cfg.ollama_model,
        "stream": False,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "options": {
            "temperature": 0.0,
            "num_predict": 256,
            "stop": ["\n\nKONTEKSTUS", "\nKÉRDÉS:", "Szabályok:", "Feladat:"]
        },
    }
    resp = requests.post(cfg.ollama_chat_endpoint, json=payload, timeout=120)
    resp.raise_for_status()
    data = resp.json()
    msg = data.get("message", {})
    return (msg.get("content") or "").strip()


# ----------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------
def cli_init(args: argparse.Namespace) -> None:
    cfg = Config(debug=args.debug)
    configure_logging(cfg.debug)

    conn = get_connection(cfg.pg_dsn)
    init_db(conn)

    docs = load_conversations(conn)
    embedder = load_embedder(cfg.embed_model)
    index_documents(conn, docs, embedder, cfg)

    conn.close()
    log.info("Inicializálás kész.")


def cli_query(args: argparse.Namespace) -> None:
    cfg = Config(debug=args.debug, no_stream=args.no_stream)
    configure_logging(cfg.debug)

    conn = get_connection(cfg.pg_dsn)
    embedder = load_embedder(cfg.embed_model)

    def answer_one(question: str) -> str:
        ticket_ids, q_emb = retrieve_top_ticket_ids(
            conn,
            question,
            embedder,
            candidate_k=cfg.candidate_k,
            top_tickets=cfg.top_tickets,
        )

        if cfg.debug:
            print(f"\n--- TOP TICKETS: {ticket_ids} ---")

        context = build_context_for_tickets(conn, q_emb, ticket_ids, top_k=cfg.top_k, cfg=cfg)
        if not context:
            return "Nem találtam releváns kontextust az adatbázisban."

        if cfg.debug:
            preview = context[:900]
            print("\n--- CONTEXT PREVIEW ---")
            print(preview)
            print("\n--- END ---\n")

        user_prompt = build_user_prompt(question, context)
        return ollama_chat(SYSTEM_PROMPT, user_prompt, cfg)

    # Egyszeri kérdés
    if args.question:
        print("\nAI válasza:\n", answer_one(args.question))
        conn.close()
        return

    # Interaktív mód
    print("Interaktív mód. Kilépés: exit / quit, vagy Ctrl+C")
    while True:
        try:
            q = input("\n> ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nKilépés.")
            break

        if not q:
            continue
        if q.lower() in {"exit", "quit"}:
            print("Kilépés.")
            break

        print("\nAI válasza:\n", answer_one(q))

    conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Magyar RAG-assistant Ollama + pgvector"
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_init = sub.add_parser("init", help="Schema ellenőrzés + újraindexelés")
    p_init.add_argument("--debug", action="store_true")
    p_init.set_defaults(func=cli_init)

    p_query = sub.add_parser("query", help="Interaktív kérdező vagy egyetlen kérdés")
    p_query.add_argument("--debug", action="store_true")
    p_query.add_argument("--no-stream", action="store_true")
    p_query.add_argument("question", nargs="?", help="Ha megadod: egyszeri kérdés. Ha üres: interaktív mód.")
    p_query.set_defaults(func=cli_query)

    args = parser.parse_args()
    args.func(args)

if __name__ == "__main__":
    main()