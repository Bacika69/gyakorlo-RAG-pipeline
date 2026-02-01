-- ----------------------------------------------------------------------
-- pgvector kiterjesztés (egyszer kell csak egyszer lefuttatni)
-- ----------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS vector;

-- ----------------------------------------------------------------------
-- (újra-építés könnyebb hibakereséshez – opcionális)
-- FK-k miatt a sorrend számít: előbb a "gyerek" táblák menjenek
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS rag_chunks;
DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS tickets;
DROP TABLE IF EXISTS users;

-- ----------------------------------------------------------------------
-- Alaptáblák
-- ----------------------------------------------------------------------
CREATE TABLE users (
    id          INTEGER PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    email       VARCHAR(150) NOT NULL,
    role        VARCHAR(50)  NOT NULL,
    created_at  TIMESTAMP    NOT NULL
);

CREATE TABLE tickets (
    id          INTEGER PRIMARY KEY,
    user_id     INTEGER NOT NULL,
    title       VARCHAR(200) NOT NULL,
    status      VARCHAR(50) NOT NULL,
    priority    VARCHAR(50) NOT NULL,
    category    VARCHAR(100) NOT NULL,
    created_at  TIMESTAMP NOT NULL,
    closed_at   TIMESTAMP NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE messages (
    id          INTEGER PRIMARY KEY,
    ticket_id   INTEGER NOT NULL,
    sender_type VARCHAR(50) NOT NULL,
    sender_name VARCHAR(100) NOT NULL,
    body        TEXT NOT NULL,
    created_at  TIMESTAMP NOT NULL,
    FOREIGN KEY (ticket_id) REFERENCES tickets(id)
);

-- ----------------------------------------------------------------------
-- RAG-chunks (vektoros index)
-- ----------------------------------------------------------------------
CREATE TABLE rag_chunks (
    id           BIGSERIAL PRIMARY KEY,
    source_table TEXT NOT NULL,
    source_id    BIGINT,
    content      TEXT NOT NULL,
    embedding    vector(384) NOT NULL
);

CREATE INDEX rag_chunks_embedding_idx
    ON rag_chunks USING ivfflat (embedding vector_l2_ops)
    WITH (lists = 100);

-- ----------------------------------------------------------------------
-- Seed adatok: users
-- ----------------------------------------------------------------------
INSERT INTO users (id, name, email, role, created_at) VALUES
(1,  'Kiss Péter',       'peter.kiss@example.com',       'customer', '2024-01-10 09:15:00'),
(2,  'Nagy Anna',        'anna.nagy@example.com',        'customer', '2024-01-12 14:22:00'),
(3,  'Support Ügynök',   'support@example.com',          'agent',    '2024-01-01 08:00:00'),
(4,  'Tóth Gábor',       'gabor.toth@example.com',       'customer', '2024-01-15 10:10:00'),
(5,  'Szabó Júlia',      'julia.szabo@example.com',      'customer', '2024-01-18 09:05:00'),
(6,  'Varga László',     'laszlo.varga@example.com',     'customer', '2024-01-20 16:30:00'),
(7,  'Kovács Dóra',      'dora.kovacs@example.com',      'customer', '2024-01-22 11:12:00'),
(8,  'Horváth Márk',     'mark.horvath@example.com',     'customer', '2024-01-25 13:55:00'),
(9,  'Molnár Eszter',    'eszter.molnar@example.com',    'customer', '2024-01-27 08:44:00'),
(10, 'Balogh Zoltán',    'zoltan.balogh@example.com',    'customer', '2024-01-29 17:21:00'),
(11, 'Fekete Nóra',      'nora.fekete@example.com',      'customer', '2024-02-02 12:07:00'),
(12, 'Papp András',      'andras.papp@example.com',      'customer', '2024-02-03 09:58:00'),
(13, 'Sipos Ádám',       'adam.sipos@example.com',       'customer', '2024-02-04 14:16:00'),
(14, 'Lakatos Katalin',  'katalin.lakatos@example.com',  'customer', '2024-02-05 10:02:00'),
(15, 'Király Bence',     'bence.kiraly@example.com',     'customer', '2024-02-05 18:40:00');

-- ----------------------------------------------------------------------
-- Seed adatok: tickets
-- ----------------------------------------------------------------------
INSERT INTO tickets (id, user_id, title, status, priority, category, created_at, closed_at) VALUES
(101, 1,  'Nem tudok belépni a fiókomba',                   'closed',      'high',   'account',   '2024-02-01 08:30:00', '2024-02-01 10:05:00'),
(102, 1,  'Számlázási probléma a januári díjjal',           'in_progress', 'medium', 'billing',   '2024-02-05 11:20:00', NULL),
(103, 2,  'Lassú az oldal betöltése',                       'open',        'low',    'technical', '2024-02-06 16:45:00', NULL),
(104, 4,  'Kétszer vonták le az előfizetés díját',          'in_progress', 'high',   'billing',   '2024-02-07 09:10:00', NULL),
(105, 5,  'Nem érkeznek meg az értesítő e-mailek',          'open',        'medium', 'account',   '2024-02-07 10:25:00', NULL),
(106, 6,  'API kulcs nem működik a staging környezetben',   'open',        'high',   'technical', '2024-02-07 14:05:00', NULL),
(107, 7,  'Szeretném módosítani az előfizetési csomagot',   'closed',      'low',    'billing',   '2024-02-08 08:15:00', '2024-02-08 09:00:00'),
(108, 8,  'Fiók törlése és adatkezelés (GDPR)',             'in_progress', 'medium', 'account',   '2024-02-08 11:40:00', NULL),
(109, 9,  'Gyakori 502-es hiba csúcsidőben',                'open',        'high',   'technical', '2024-02-09 16:20:00', NULL),
(110, 10, 'Kuponkódot nem fogad el a fizetésnél',           'closed',      'medium', 'billing',   '2024-02-10 09:33:00', '2024-02-10 10:10:00'),
(111, 11, 'Nem tudom frissíteni a jelszavam',               'open',        'medium', 'account',   '2024-02-10 13:05:00', NULL),
(112, 12, 'Importnál hibásan jelennek meg az ékezetek',     'in_progress', 'medium', 'technical', '2024-02-11 15:50:00', NULL),
(113, 13, 'Számla letöltése nem működik',                   'open',        'low',    'billing',   '2024-02-12 10:12:00', NULL),
(114, 14, 'Lassú admin felület nagy adatmennyiségnél',      'open',        'low',    'technical', '2024-02-12 17:30:00', NULL),
(115, 15, 'Kétfaktoros azonosítás bekapcsolása',            'closed',      'low',    'account',   '2024-02-13 09:00:00', '2024-02-13 09:35:00');

-- ----------------------------------------------------------------------
-- Seed adatok: messages
-- ----------------------------------------------------------------------
INSERT INTO messages (id, ticket_id, sender_type, sender_name, body, created_at) VALUES
(1001, 101, 'customer', 'Kiss Péter',
 'Sziasztok, ma reggel óta nem tudok belépni a fiókomba. A rendszer azt írja, hogy hibás jelszó, pedig biztosan jól írom be.',
 '2024-02-01 08:32:00'),
(1002, 101, 'agent', 'Support Ügynök',
 'Kedves Péter! Köszönjük a jelzését. Ellenőriztem a rendszerben, és úgy látom, hogy tegnap jelszóváltoztatás történt. Megpróbálta már a "Elfelejtett jelszó" funkciót?',
 '2024-02-01 08:50:00'),
(1003, 101, 'customer', 'Kiss Péter',
 'Igen, próbáltam, de nem kaptam meg az e-mailt a jelszó visszaállításához.',
 '2024-02-01 09:05:00'),
(1004, 101, 'agent', 'Support Ügynök',
 'Most manuálisan újraküldtem a jelszó-visszaállító e-mailt. Kérem, ellenőrizze a spam mappát is. Ha továbbra sem érkezik meg, jelezze.',
 '2024-02-01 09:20:00'),
(1005, 101, 'customer', 'Kiss Péter',
 'Megérkezett, köszönöm! Sikerült belépnem.',
 '2024-02-01 09:55:00'),
(1006, 101, 'agent', 'Support Ügynök',
 'Örülök, hogy sikerült megoldani a problémát. A jegyet lezárom, de bármikor újraírhat, ha gond lenne.',
 '2024-02-01 10:05:00'),

(1007, 102, 'customer', 'Kiss Péter',
 'A januári számlámon magasabb összeg szerepel, mint amire számítottam. Nem értem, miért.',
 '2024-02-05 11:22:00'),
(1008, 102, 'agent', 'Support Ügynök',
 'Megnézem a számlázási előzményeit, és visszajelzek a részletekkel.',
 '2024-02-05 11:40:00'),
(1009, 102, 'agent', 'Support Ügynök',
 'Átnéztem a számlát: a magasabb összeg oka, hogy a csomagja automatikusan frissült a "Pro" csomagra január 1-jén. Erről korábban e-mailben küldtünk értesítést.',
 '2024-02-05 12:10:00'),
(1010, 102, 'customer', 'Kiss Péter',
 'Értem, de nem emlékszem, hogy kértem volna frissítést. Vissza lehet állítani az előző csomagot?',
 '2024-02-05 12:25:00'),

(1011, 103, 'customer', 'Nagy Anna',
 'Az oldal nagyon lassan tölt be, különösen délutánonként. Néha 10-15 másodpercet is várnom kell.',
 '2024-02-06 16:47:00'),
(1012, 103, 'agent', 'Support Ügynök',
 'Köszönjük a visszajelzést! Továbítom a fejlesztői csapatnak a teljesítményproblémát, és amint van friss információ, jelentkezem.',
 '2024-02-06 17:05:00'),

(1013, 104, 'customer', 'Tóth Gábor',
 'Sziasztok! A februári előfizetést mintha kétszer vonták volna le. Tudnátok ellenőrizni?',
 '2024-02-07 09:12:00'),
(1014, 104, 'agent', 'Support Ügynök',
 'Kedves Gábor! Köszönöm a jelzést. Megnézem a tranzakciókat és visszajelzek.',
 '2024-02-07 09:20:00'),
(1015, 104, 'agent', 'Support Ügynök',
 'Két terhelést látok: az egyik sikertelen volt, de függőben maradt. A bank 1-3 munkanapon belül feloldja. Küldjek igazolást?',
 '2024-02-07 09:55:00'),
(1016, 104, 'customer', 'Tóth Gábor',
 'Igen, kérnék egy igazolást, mert a bank kéri.',
 '2024-02-07 10:05:00'),
(1017, 104, 'agent', 'Support Ügynök',
 'Rendben, elküldtem e-mailben a tranzakció-igazolást. Ha nem érkezik meg, jelezze.',
 '2024-02-07 10:18:00'),

(1018, 105, 'customer', 'Szabó Júlia',
 'Nem kapok értesítő e-maileket (jelszóváltás, számla). A spam mappában sincs.',
 '2024-02-07 10:28:00'),
(1019, 105, 'agent', 'Support Ügynök',
 'Kedves Júlia! Ellenőrzöm az e-mail kézbesítési logokat. Melyik címre várja az üzeneteket?',
 '2024-02-07 10:40:00'),
(1020, 105, 'customer', 'Szabó Júlia',
 'A julia.szabo@example.com címre.',
 '2024-02-07 10:43:00'),
(1021, 105, 'agent', 'Support Ügynök',
 'A rendszerben látok több visszapattanást (bounce). Valószínűleg korábban tiltólistára került a cím. Feloldottam, kérem próbálja újra a jelszóemlékeztetőt.',
 '2024-02-07 11:10:00'),
(1022, 105, 'customer', 'Szabó Júlia',
 'Most már megjött a teszt e-mail, köszönöm!',
 '2024-02-07 11:15:00'),

(1023, 106, 'customer', 'Varga László',
 'A staging API-ban 401-et kapok, pedig a kulcs aktív. Productionben jó.',
 '2024-02-07 14:10:00'),
(1024, 106, 'agent', 'Support Ügynök',
 'Köszönöm! A staging külön kulcskészletet használ. Tudna küldeni egy request-id-t vagy időbélyeget?',
 '2024-02-07 14:25:00'),
(1025, 106, 'customer', 'Varga László',
 'Request-id: stg-7f2a1. Idő: 14:07 körül.',
 '2024-02-07 14:28:00'),
(1026, 106, 'agent', 'Support Ügynök',
 'Megvan: a stagingben IP allowlist van bekapcsolva az Ön fiókján. Hozzáadjam a jelenlegi IP-t, vagy kapcsoljuk ki?',
 '2024-02-07 14:50:00'),
(1027, 106, 'customer', 'Varga László',
 'Kérem adják hozzá: 203.0.113.42',
 '2024-02-07 14:55:00'),
(1028, 106, 'agent', 'Support Ügynök',
 'Rögzítettem az IP-t az allowlistben. Próbálja újra, elvileg megszűnt a 401.',
 '2024-02-07 15:05:00'),

(1029, 107, 'customer', 'Kovács Dóra',
 'Szeretném a csomagot Basic-re visszaváltani a következő ciklustól.',
 '2024-02-08 08:18:00'),
(1030, 107, 'agent', 'Support Ügynök',
 'Rendben. Megerősítem: a váltás a következő számlázási napon lépjen életbe?',
 '2024-02-08 08:25:00'),
(1031, 107, 'customer', 'Kovács Dóra',
 'Igen, a következő ciklustól legyen Basic.',
 '2024-02-08 08:28:00'),
(1032, 107, 'agent', 'Support Ügynök',
 'Beállítottam a váltást a következő ciklusra. A jegyet lezárom.',
 '2024-02-08 09:00:00'),

(1033, 108, 'customer', 'Horváth Márk',
 'Szeretném törölni a fiókomat, és érdekel, hogy az adataim meddig maradnak meg.',
 '2024-02-08 11:45:00'),
(1034, 108, 'agent', 'Support Ügynök',
 'Köszönöm! A fióktörlés indítható, de előtte szükséges egy tulajdonosi megerősítés. Küldök egy megerősítő e-mailt.',
 '2024-02-08 12:05:00'),
(1035, 108, 'customer', 'Horváth Márk',
 'Megkaptam, megerősítettem.',
 '2024-02-08 12:20:00'),
(1036, 108, 'agent', 'Support Ügynök',
 'Rendben. A fiók deaktiválása megtörtént. Számlázási adatokat jogszabály szerint megőrizzük, egyéb profiladatok törlésre kerülnek.',
 '2024-02-08 12:40:00'),

(1037, 109, 'customer', 'Molnár Eszter',
 'Csúcsidőben sokszor 502-es hibát kapok. Van valami fennakadás?',
 '2024-02-09 16:22:00'),
(1038, 109, 'agent', 'Support Ügynök',
 'Köszönöm a jelzést. Kérem írja meg, melyik oldalon és kb. milyen időpontokban jelentkezik.',
 '2024-02-09 16:35:00'),
(1039, 109, 'customer', 'Molnár Eszter',
 'Leginkább a dashboardon, 16:00-18:00 között.',
 '2024-02-09 16:38:00'),
(1040, 109, 'agent', 'Support Ügynök',
 'Azonosítottunk egy terhelési csúcsot. Ideiglenesen skáláztunk, a fejlesztők vizsgálják a gyökérokot.',
 '2024-02-09 17:10:00'),
(1041, 109, 'agent', 'Support Ügynök',
 'Frissítés: egy hibás cache-beállítás okozta. Javítva, monitorozzuk. Kérem jelezze, ha ismét előjön.',
 '2024-02-09 18:05:00'),

(1042, 110, 'customer', 'Balogh Zoltán',
 'A kuponkódot nem fogadja el fizetésnél, pedig még érvényesnek tűnik.',
 '2024-02-10 09:35:00'),
(1043, 110, 'agent', 'Support Ügynök',
 'Megnézem a kupon feltételeit. Mi a kuponkód pontosan?',
 '2024-02-10 09:40:00'),
(1044, 110, 'customer', 'Balogh Zoltán',
 'Kód: FEB10',
 '2024-02-10 09:42:00'),
(1045, 110, 'agent', 'Support Ügynök',
 'A FEB10 csak havi csomagra érvényes, évesre nem. Átállítom a kosarat havi számlázásra, vagy adok alternatív kupont.',
 '2024-02-10 09:55:00'),
(1046, 110, 'customer', 'Balogh Zoltán',
 'A havi jó lesz, köszönöm.',
 '2024-02-10 10:02:00'),
(1047, 110, 'agent', 'Support Ügynök',
 'Átállítottam havi számlázásra, így működnie kell. Lezárom a jegyet.',
 '2024-02-10 10:10:00'),

(1048, 111, 'customer', 'Fekete Nóra',
 'Jelszófrissítésnél azt írja, hogy "token lejárt", pedig azonnal kattintok.',
 '2024-02-10 13:07:00'),
(1049, 111, 'agent', 'Support Ügynök',
 'Köszönöm! Előfordul, hogy több reset e-mail érkezik, és a régebbi linkre kattint. Küldök egy friss linket.',
 '2024-02-10 13:18:00'),
(1050, 111, 'customer', 'Fekete Nóra',
 'Most sikerült, köszönöm. A böngésző gyorsítótár okozhatta?',
 '2024-02-10 13:26:00'),
(1051, 111, 'agent', 'Support Ügynök',
 'Igen, ritkán előfordul. Ha újra jelentkezne, inkognitó ablakból is érdemes kipróbálni.',
 '2024-02-10 13:35:00'),

(1052, 112, 'customer', 'Papp András',
 'CSV importnál az ékezetes betűk "?"-ként jelennek meg.',
 '2024-02-11 15:52:00'),
(1053, 112, 'agent', 'Support Ügynök',
 'Köszönöm. Milyen kódolású a fájl (UTF-8, ISO-8859-2)? Tudna egy mintasort küldeni?',
 '2024-02-11 16:05:00'),
(1054, 112, 'customer', 'Papp András',
 'Excelből mentettem, valószínű ANSI. Küldök mintát: "Árvíztűrő tükörfúrógép".',
 '2024-02-11 16:10:00'),
(1055, 112, 'agent', 'Support Ügynök',
 'Valószínűleg nem UTF-8. Kérem mentse "CSV UTF-8"-ként, vagy állítsa át a mentést UTF-8-ra. Ha kell, adok lépésről-lépésre útmutatót.',
 '2024-02-11 16:25:00'),
(1056, 112, 'customer', 'Papp András',
 'UTF-8-ként mentve már jó. Köszönöm!',
 '2024-02-11 16:40:00'),

(1057, 113, 'customer', 'Sipos Ádám',
 'A számla letöltésekor üres PDF-et kapok.',
 '2024-02-12 10:14:00'),
(1058, 113, 'agent', 'Support Ügynök',
 'Köszönöm. Melyik böngészőt használja, és mikor jelentkezett először?',
 '2024-02-12 10:25:00'),
(1059, 113, 'customer', 'Sipos Ádám',
 'Chrome, ma reggel vettem észre.',
 '2024-02-12 10:28:00'),
(1060, 113, 'agent', 'Support Ügynök',
 'Lehet, hogy egy böngészőbővítmény blokkolja a letöltést. Próbálja meg inkognitó módban, illetve kapcsolja ki az adblockert a domainre.',
 '2024-02-12 10:45:00'),

(1061, 114, 'customer', 'Lakatos Katalin',
 'Az admin felület nagyon belassul, ha 50.000+ rekordot listázok.',
 '2024-02-12 17:35:00'),
(1062, 114, 'agent', 'Support Ügynök',
 'Köszönöm. Pontosan melyik lista oldalon történik? Van szűrő/sorrend beállítva?',
 '2024-02-12 17:50:00'),
(1063, 114, 'customer', 'Lakatos Katalin',
 'Felhasználók lista, név szerint rendezve, szűrő nélkül.',
 '2024-02-12 17:55:00'),
(1064, 114, 'agent', 'Support Ügynök',
 'Értem. Javaslat: kapcsoljuk be a szerveroldali lapozást és indexeljük a rendezési mezőt. Továbbítom a fejlesztőknek.',
 '2024-02-12 18:10:00'),

(1065, 115, 'customer', 'Király Bence',
 'Szeretném bekapcsolni a kétfaktoros azonosítást, de nem találom a menüpontot.',
 '2024-02-13 09:02:00'),
(1066, 115, 'agent', 'Support Ügynök',
 'A Beállítások > Biztonság menüben található. Ha elküldi a képernyőn látható opciókat, segítek pontosítani.',
 '2024-02-13 09:10:00'),
(1067, 115, 'customer', 'Király Bence',
 'Megvan, csak a mobil nézet elrejtette. Most már látom.',
 '2024-02-13 09:20:00'),
(1068, 115, 'agent', 'Support Ügynök',
 'Szuper. Aktiválás után érdemes mentőkódokat is letölteni. Lezárom a jegyet.',
 '2024-02-13 09:35:00'),

(1069, 102, 'agent', 'Support Ügynök',
 'Péter, meg tudjuk oldani a csomag visszaállítást a következő ciklustól. Szeretné, hogy januárra jóváírást is indítsunk?',
 '2024-02-05 12:40:00'),
(1070, 102, 'customer', 'Kiss Péter',
 'Igen, jó lenne valamilyen jóváírás, mert nem én kértem az emelést.',
 '2024-02-05 12:55:00'),
(1071, 102, 'agent', 'Support Ügynök',
 'Rendben, indítok egy részleges jóváírást és a csomagot visszaállítjuk Basic-re a következő számlázási napon.',
 '2024-02-05 13:20:00'),
(1072, 102, 'customer', 'Kiss Péter',
 'Köszönöm, így rendben.',
 '2024-02-05 13:35:00'),

(1073, 103, 'agent', 'Support Ügynök',
 'Anna, frissítés: a délutáni lassulást egy túlterhelt adatbázis-lekérdezés okozta. Optimalizáltuk, a válaszidő javult.',
 '2024-02-07 09:00:00'),
(1074, 103, 'customer', 'Nagy Anna',
 'Most már érezhetően gyorsabb, köszönöm a gyors intézkedést!',
 '2024-02-07 09:12:00');
