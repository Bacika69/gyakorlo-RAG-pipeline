# Magyar RAG Assistant – Ollama + pgvector + Sentence-Transformers

Ez a projekt egy **magyar nyelvű RAG (Retrieval-Augmented Generation) kérdés–válasz rendszer**, amely:

- PostgreSQL-ben tárolt ticket-beszélgetésekből dolgozik
- `sentence-transformers` embeddingeket használ
- `pgvector` segítségével végez vektoros keresést
- **Ollama** lokális LLM-et használ válaszgeneráláshoz
- CLI-alapú (`init`, `query` parancsok)

---

## 1. Funkciók röviden

- Ticket beszélgetések automatikus feldolgozása  
- Intelligens chunkolás (paragrafus + mondat sliding window)  
- Topic címkézés (`[Jegy – Belépési problémák]`, stb.)  
- Kétlépcsős retrieval  
- Magyar nyelvű, auditálható LLM válasz  
- Szó szerinti idézet a forrásból  

---

## 2. Követelmények

### Szoftver
- Python 3.10+  
- PostgreSQL 14+  
- pgvector extension  
- Ollama  

### Hardver
- CPU-n futtatható  
- GPU opcionális  

---

## 3. Telepítés

### Virtuális környezet
```bash
python -m venv .venv
source .venv/bin/activate
```

### Függőségek
```bash
pip install psycopg2-binary pgvector sentence-transformers tiktoken requests numpy
```

---

## 4. PostgreSQL (Docker – ajánlott)

```yaml
services:
  db:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_DB: ai_sql
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "15432:5432"
```

Indítás:
```bash
docker compose up -d
```

---

## 5. Ollama

```bash
ollama pull llama3.2:3b
```

Ellenőrzés:
```bash
curl http://localhost:11434/api/tags
```

---

## 6. Futtatás

### Indexelés
```bash
python data.py init
```

### Kérdezés
```bash
python data.py query
python data.py query "Mi volt a probléma?"
```

---

## 7. Hibák

- pgvector hiányzik → rossz Docker image  
- Embedding dimenzió nem 384  
- Üres `rag_chunks` tábla  

---

## 8. Licenc
Belső / projekt-specifikus felhasználás.
