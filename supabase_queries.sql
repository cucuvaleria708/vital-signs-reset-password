-- ============================================================
--  SUPABASE — Tabele pentru Profil Medical și Jurnal
--  Monitor Sănătate · Cucu Valeria Alexandra
--  Rulează aceste comenzi în Supabase SQL Editor
-- ============================================================


-- ── 1. TABEL: medical_profiles ──────────────────────────────────────────────
--  Un rând per utilizator (user_id = UUID din auth.users).
--  Sincronizat cu Room DB local la fiecare login.

CREATE TABLE IF NOT EXISTS medical_profiles (
    id          UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    gender      TEXT        NOT NULL DEFAULT 'M' CHECK (gender IN ('M', 'F')),
    age         INTEGER     CHECK (age BETWEEN 1 AND 120),
    weight      REAL        CHECK (weight BETWEEN 30 AND 300),
    height_cm   REAL        CHECK (height_cm BETWEEN 50 AND 250),
    blood_type  TEXT        CHECK (blood_type IN ('A+','A-','B+','B-','AB+','AB-','O+','O-','')),
    created_at  TIMESTAMPTZ DEFAULT now(),
    updated_at  TIMESTAMPTZ DEFAULT now(),
    UNIQUE (user_id)
);

-- Row Level Security: fiecare utilizator vede și modifică doar profilul propriu
ALTER TABLE medical_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Utilizator vede propriul profil"
    ON medical_profiles FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Utilizator creează propriul profil"
    ON medical_profiles FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Utilizator actualizează propriul profil"
    ON medical_profiles FOR UPDATE
    USING (auth.uid() = user_id);

-- Trigger: actualizează updated_at automat la fiecare modificare
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_medical_profiles_updated_at
    BEFORE UPDATE ON medical_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();


-- ── 2. TABEL: journal_entries ────────────────────────────────────────────────
--  Jurnal personal de sănătate. Fiecare intrare poate fi legată opțional de
--  o măsurătoare (measurement_id) dacă sincronizezi și tabelul measurements.

CREATE TABLE IF NOT EXISTS journal_entries (
    id              UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    measurement_id  BIGINT,                         -- FK opțional spre tabelul measurements
    entry_date      TIMESTAMPTZ NOT NULL DEFAULT now(),
    title           TEXT        NOT NULL DEFAULT '',
    notes           TEXT        NOT NULL DEFAULT '',
    mood            SMALLINT    NOT NULL DEFAULT 3 CHECK (mood BETWEEN 1 AND 5),
    tags            TEXT[]      NOT NULL DEFAULT '{}',  -- ex: '{sport,dimineata}'
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_journal_entries_user_id    ON journal_entries(user_id);
CREATE INDEX idx_journal_entries_entry_date ON journal_entries(entry_date DESC);

-- Row Level Security
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Utilizator vede propriul jurnal"
    ON journal_entries FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Utilizator adaugă în jurnal"
    ON journal_entries FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Utilizator modifică propria intrare"
    ON journal_entries FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Utilizator șterge propria intrare"
    ON journal_entries FOR DELETE
    USING (auth.uid() = user_id);

CREATE TRIGGER trg_journal_entries_updated_at
    BEFORE UPDATE ON journal_entries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();


-- ── 3. TABEL: measurements (dacă vrei să sincronizezi și măsurătorile) ───────
--  Opțional — dacă dorești backup în cloud al datelor din Room DB local.

CREATE TABLE IF NOT EXISTS measurements (
    id                  BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id             UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    start_time          BIGINT      NOT NULL,   -- epoch ms
    end_time            BIGINT      NOT NULL,
    average_bpm         INTEGER,
    min_bpm             INTEGER,
    max_bpm             INTEGER,
    connection_method   TEXT,
    measurement_type    TEXT        NOT NULL DEFAULT 'PULS'
                                    CHECK (measurement_type IN ('PULS','EKG','AI_ECG')),
    notes               TEXT,
    ai_result           TEXT,
    ai_probabilities    TEXT,
    created_at          TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE measurements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Utilizator vede propriile măsurători"
    ON measurements FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Utilizator inserează măsurătoare"
    ON measurements FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Utilizator șterge propria măsurătoare"
    ON measurements FOR DELETE
    USING (auth.uid() = user_id);


-- ── 4. INTEROGĂRI UTILE ──────────────────────────────────────────────────────
--
--  ATENȚIE: auth.uid() returnează NULL când rulezi din SQL Editor (ești postgres,
--  nu un utilizator autentificat). Pentru testare manuală în SQL Editor înlocuiește
--  auth.uid() cu UUID-ul real al utilizatorului, obținut astfel:
--
--      SELECT id, email FROM auth.users;
--
--  În aplicația Android auth.uid() funcționează corect automat.

-- Găsește UUID-ul unui utilizator după email (rulează întâi asta)
SELECT id, email FROM auth.users WHERE email = 'adresa@email.ro';

-- Obține profilul medical (înlocuiește UUID-ul)
SELECT * FROM medical_profiles
WHERE user_id = 'inlocuieste-cu-uuid-real-din-auth-users';

-- Upsert profil medical pentru testare din SQL Editor
-- (în aplicație se face automat prin MedicalProfileRepository)
INSERT INTO medical_profiles (user_id, gender, age, weight)
VALUES ('inlocuieste-cu-uuid-real-din-auth-users', 'F', 25, 60.5)
ON CONFLICT (user_id) DO UPDATE
    SET gender     = EXCLUDED.gender,
        age        = EXCLUDED.age,
        weight     = EXCLUDED.weight,
        updated_at = now();

-- Ultimele 20 intrări din jurnal
SELECT * FROM journal_entries
WHERE user_id = 'inlocuieste-cu-uuid-real-din-auth-users'
ORDER BY entry_date DESC
LIMIT 20;

-- Adaugă o intrare în jurnal pentru testare
INSERT INTO journal_entries (user_id, title, notes, mood, tags)
VALUES ('inlocuieste-cu-uuid-real-din-auth-users',
        'Dimineață', 'M-am simțit bine după alergat.', 4, '{sport,dimineata}');

-- Statistici BPM pe ultimele 30 de zile
SELECT
    DATE(TO_TIMESTAMP(start_time / 1000)) AS zi,
    ROUND(AVG(average_bpm)::numeric, 1)  AS bpm_mediu,
    MIN(min_bpm)                          AS bpm_minim,
    MAX(max_bpm)                          AS bpm_maxim,
    COUNT(*)                              AS nr_masuratori
FROM measurements
WHERE user_id = auth.uid()
  AND start_time >= EXTRACT(EPOCH FROM now() - INTERVAL '30 days') * 1000
GROUP BY zi
ORDER BY zi DESC;
