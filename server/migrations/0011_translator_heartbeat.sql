-- When each scheduled step last ran (#49 review, Roman 16 Oct). The translator
-- writes its time at the start of every run. The release waits for the
-- translations only while the translator has run in the last 10 minutes: when
-- it has not (its new cron trigger can take about an hour to start firing, #50,
-- or the trigger stopped), the summarizer's run releases each summarized
-- decision at once, so the English feed never freezes, and every language fills
-- in later at the English places, as after an automatic pause.
CREATE TABLE step_runs (
  step TEXT PRIMARY KEY,
  at   TEXT NOT NULL
);
