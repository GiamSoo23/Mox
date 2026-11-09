# Installing Mox

About ten minutes, most of it waiting for Supabase. You need:

- a Mac with macOS 13 or later,
- an Android phone with Android 8 or later,
- a free [Supabase](https://supabase.com) account. Mox keeps your files in
  **your own** Supabase project, so nobody else holds them. If you don't have
  an account, you can create one during setup.

## 1. Install Mox on the Mac

1. Download **Mox-macOS.zip** from the
   [latest release](https://github.com/GiamSoo23/Mox/releases/latest) and
   double-click it.
2. Open **Mox.app**.
3. macOS warns that it can't check the app for malicious software, because
   Mox isn't notarized by Apple yet. To open it anyway:
   - **macOS 15 or later:** click **Done**, open **System Settings → Privacy &
     Security**, scroll down to "Mox was blocked", and click **Open Anyway**.
   - **macOS 13–14:** right-click Mox.app, choose **Open**, then **Open** again.

   You only do this once. To check the download first, compare it with
   `SHA256SUMS.txt` from the same release: `shasum -a 256 Mox-macOS.zip`.

When it opens, Mox offers to **move itself to Applications**. Accept, and it
reopens from there.

Mox lives in the menu bar (a red box icon). macOS hides menu bar icons when
the bar is full, and no app can claim a spot. If you can't see it, open Mox
again from Applications: a window appears with **Pair a Phone…**, **Set Up
Again…** and **Quit**, and Mox shows in the Dock while that window is open.

## 2. Set it up

The setup window opens on the first launch. You can also open it from the
menu bar: **Set Up Mox…**

1. Click **Sign in with Supabase**. Your browser opens. Sign in, choose your
   organization, and allow Mox. Then go back to Mox.

   Mox uses this sign-in only to set up your project. It doesn't keep it.
2. Choose where Mox keeps your files:
   - **Create a new project** (recommended). Supabase takes a few minutes to
     start it.
   - **A project you already have.** Mox adds its own tables in a separate
     `mox` schema and doesn't touch your data.
3. Wait for the checklist to finish. Mox then shows a QR code.

### If you already have two free projects

Supabase's free plan allows two active projects. When you're at the limit,
Mox recommends installing into one of them. You can also pause a project
you don't use in the [Supabase dashboard](https://supabase.com/dashboard).
Pausing keeps its data, and you can restore it later.

A paused project shows as "(paused)" and can't be chosen. Restore it in the
dashboard first, then reopen **Set Up Mox…**.

### If other people manage the project

Mox warns you when other accounts administer the Supabase organization.
Those people could see the files you send. Choose a project only you manage
if that matters to you.

### Signing in without the browser

If **Sign in with Supabase** isn't there (an app you built yourself), or
doesn't work, use **Use an access token instead**:

1. Create a token at
   [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens).
2. Paste it into Mox. It's used only for this setup and isn't saved.
3. Delete the token afterwards if you like.

## 3. Pair your phone

1. Point the phone's camera at the QR code and open the link.
2. If Mox isn't on the phone yet, tap **Download Mox for Android** and install
   it. Android asks you to allow installs from your browser the first time.
3. Tap **Open in Mox**. Mox says **Paired with** your Mac's name.

The QR code contains Mox's password for your project, so don't share it or
send a screenshot of it. To pair another phone later, choose **Pair a
Phone…** in the menu bar.

## 4. Use it

- **Mac → phone:** select a file in Finder and press **⌘⇧M**.
- **Phone → Mac:** in any app, tap **Share → Mox**. The file lands in
  `~/Downloads` and on the clipboard.

## Something went wrong

| What you see | What to do |
|---|---|
| "Another app is using port 53682" | Quit the app using it, or use an access token instead |
| "Your account already has the maximum number of free projects" | Choose a project you already have, or pause one (see above) |
| "This project is paused" | Restore it in the Supabase dashboard, then try again |
| "Mox is already set up in this project" | **Set Up Again** creates a new Mox user. Your paired devices then need to pair again |
| The phone says it can't sign in | Pair again from **Pair a Phone…** on the Mac |

Still stuck? [Open an issue](https://github.com/GiamSoo23/Mox/issues/new).
