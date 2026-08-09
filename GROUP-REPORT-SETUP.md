# Group report — setup

The game now consolidates results automatically. The facilitator puts one **workshop code**
on screen, every player enters it before they start, and the room view builds a live group
report from everyone who finishes under that code.

Until you complete the steps below, the game still works exactly as it did — it just falls
back to the facilitator pasting result codes by hand.

---

## What gets stored

Per participant, one row: four scores, the tie-break winner if there was one, the pressure
tendency if they answered, and a timestamp. Plus a random device id, generated in the
browser, used only to stop a replay from counting twice.

Not stored: names, email, IP-linked identifiers, individual duel answers, the written
commitment on the last screen. That stays on the player's own device.

---

## 1. Create the Supabase project

1. Sign up at https://supabase.com and create a new project. The free tier is far more than
   a workshop needs.
2. Choose a region close to your participants — Singapore, if that is where you run.
3. Wait for the project to finish provisioning (a minute or two).

## 2. Create the table and functions

1. In the dashboard, open **SQL Editor → New query**.
2. Paste the entire contents of [`supabase-setup.sql`](supabase-setup.sql) and click **Run**.
3. You should see `Success. No rows returned`.

This creates one table and two functions, and locks the table down so the public key cannot
read, write or delete rows directly. Everything goes through the two functions, which
validate their inputs and enforce the 5-participant anonymity gate inside the database.

## 3. Point the game at your project

1. In the dashboard, open **Project Settings → API**.
2. Copy the **Project URL** and the **anon / public** key.
3. Open `energy-duels-game.html`, find this block near the top of the `<script>`:

   ```js
   const SUPABASE_URL      = '';
   const SUPABASE_ANON_KEY = '';
   ```

4. Paste your two values between the quotes and save.

The anon key is designed to be public and is safe in a page anyone can view. It is not a
secret. Never paste the **service_role** key here — that one bypasses every protection above.

## 4. Deploy

Copy the file over `duels/index.html` in the `where-you-lead-from` repo and push. GitHub
Pages picks it up in a minute or so.

---

## Running a session

**Before the room arrives**

1. Open the game, click *Facilitating? Open the room view*.
2. Click **＋ New code**. A six-character code appears, along with a join link.
3. Put the code on your slide. Participants type it on the welcome screen. If you would
   rather share a link or QR, use the join link — it fills the code in automatically.

**While they play**

The room view polls every 12 seconds and shows a running count. The report itself stays
locked until 5 people have finished, so nobody's individual result can be inferred from a
small room.

**Debriefing**

The report gives you four things:

- **Lead energies** — how many people lead from each. Someone with two closely paired
  energies is counted under both, so the tiles can total more than the headcount.
- **Average access rate** — the room's overall pull toward each energy.
- **A callout** naming the room's most and least accessed energy. Usually the most useful
  sentence to read aloud.
- **Under sustained pressure** — the group's overplay tendencies, held separately from the
  energy scores, as the spec requires.

**Afterwards**

**🖨 Print / PDF** gives a clean report with the controls stripped out. **↓ CSV** gives one
anonymous row per participant for a post-workshop pack.

---

## Notes and limits

- **Codes are guessable in principle.** Six characters from a 31-character alphabet is about
  a billion combinations, so casual guessing will not find a live room. But the data behind
  a code is four anonymous numbers, so the consequence of a guess is small. Generate a fresh
  code per session rather than reusing one.
- **A player can join only one workshop per game.** Changing the code on the welcome screen
  before starting is fine; changing it mid-game is not supported.
- **Replaying under the same code replaces** that device's earlier result rather than adding
  a second one.
- **A room is capped at 500 results** as a flood guard.
- **Offline?** Switch the room view to **📋 Paste codes** and collect the `DUEL#a.b.c.d`
  codes by hand, exactly as before.
- **Clearing old data:** `supabase-setup.sql` ends with a commented-out delete statement you
  can run periodically, or schedule with `pg_cron`.

## If something goes wrong

| Symptom | Likely cause |
| --- | --- |
| *"No group-report backend configured yet"* | Step 3 not done, or the file was deployed without the values |
| *"Could not reach the group report"* on the player's screen | Wrong URL or key, or step 2 not run. Their result is still safe on their device |
| Report stays locked | Fewer than 5 people have finished under that exact code |
| Count is lower than the number of people who played | Someone mistyped the code, or skipped it entirely |
