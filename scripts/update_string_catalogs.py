#!/usr/bin/env python3
"""Fills the String Catalogs from the strings the compiler extracted, with English translations.

Xcode's IDE syncs String Catalogs on build; xcodebuild does not. Run this after building to add
new German source strings (development language) and their English translations:

    xcodebuild -project BreakTimer.xcodeproj -scheme BreakTimer \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build
    python3 scripts/update_string_catalogs.py

Existing entries and translations made in Xcode are kept; only missing keys are added.
Keys without an English translation below are added untranslated (Xcode shows them as "New").
"""

import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build/DerivedData/Build/Intermediates.noindex/BreakTimer.build/Debug-iphonesimulator")
TARGETS = {
    "BreakTimer": os.path.join(ROOT, "BreakTimer/Resources/Localizable.xcstrings"),
    "BreakTimerWidget": os.path.join(ROOT, "BreakTimerWidget/Localizable.xcstrings"),
}

DO_NOT_TRANSLATE = {"BreakTimer", "+%@", "Support", "System", "Version", "Budget"}

EN = {
    "%@, %@": "%1$@, %2$@",
    "%@ / %lld Min.": "%1$@ / %2$lld min",
    "%@ von %@ genutzt": "%1$@ of %2$@ used",
    "%@ von %lld Min.": "%1$@ of %2$lld min",
    "%@ von %lld Minuten": "%1$@ of %2$lld minutes",
    "%@ von %lld Minuten, über Budget": "%1$@ of %2$lld minutes, over budget",
    "%@ über dem Budget": "%@ over budget",
    "%@ übrig": "%@ left",
    "%@ – läuft": "%@ – running",
    "%lld Min.": "%lld min",
    "%lld von %lld Tagen": "%1$lld of %2$lld days",
    "30 Tage": "30 days",
    "7 Tage": "7 days",
    "Ab jetzt zählt deine Pause als Überziehung.": "From now on, your break counts as overtime.",
    "Abbrechen": "Cancel",
    "Abmelden": "Sign Out",
    "Abmelden?": "Sign out?",
    "Alle Pausen und Einstellungen werden von diesem iPhone entfernt. Sie bleiben in deinem Konto gespeichert.":
        "All breaks and settings will be removed from this iPhone. They stay saved in your account.",
    "Anmelden": "Sign In",
    "Auf diesem iPhone ist Mail nicht eingerichtet. Teile das Protokoll mit einer beliebigen Mail-App.":
        "Mail isn't set up on this iPhone. Share the log with any mail app.",
    "Ausführliche Protokollierung": "Verbose Logging",
    "Bearbeiten": "Edit",
    "Beenden": "End",
    "Beendet die laufende Pause.": "Ends the running break.",
    "Beginn": "Start",
    "Behalte dein tägliches Pausenbudget im Blick.": "Keep an eye on your daily break budget.",
    "Bei 5 Minuten Restzeit": "With 5 minutes left",
    "Bestätige deine E-Mail-Adresse": "Confirm your email address",
    "Bitte bestätige zuerst deine E-Mail-Adresse.": "Please confirm your email address first.",
    "Bitte gib dein Passwort ein.": "Please enter your password.",
    "Bitte gib eine gültige E-Mail-Adresse ein.": "Please enter a valid email address.",
    "BreakTimer · Nicht angemeldet": "BreakTimer · Not signed in",
    "Darstellung": "Appearance",
    "Das Ende darf nicht in der Zukunft liegen.": "The end can't be in the future.",
    "Das Ende muss nach dem Beginn liegen.": "The end must be after the start.",
    "Das Passwort ist zu schwach. Wähle ein längeres oder komplexeres Passwort.":
        "This password is too weak. Choose a longer or more complex one.",
    "Das Protokoll enthält technische Daten und Pausenzeiten, aber keine Passwörter.":
        "The log contains technical data and break times, but no passwords.",
    "Das Protokoll hilft dem Support bei der Fehlersuche. Es wird nur auf diesem iPhone gelöscht.":
        "The log helps support find problems. It is only deleted on this iPhone.",
    "Das Protokoll konnte nicht erstellt werden.": "The log couldn't be created.",
    "Das neue Passwort muss sich vom bisherigen unterscheiden.": "The new password must be different from the old one.",
    "Dauer": "Duration",
    "Dein Konto, alle Pausen, Einstellungen und das Protokoll werden unwiderruflich gelöscht. Gib zur Bestätigung „%@“ ein.":
        "Your account, all breaks, settings and the log will be deleted permanently. Type “%@” to confirm.",
    "Dein Passwort wurde geändert.": "Your password has been changed.",
    "Dein Pausenbudget für heute ist gleich aufgebraucht.": "Your break budget for today is almost used up.",
    "Deine Pause läuft seit %@ Uhr. Wann hast du sie tatsächlich beendet?":
        "Your break has been running since %@. When did it actually end?",
    "Deine Pausen werden auf dem Gerät gespeichert und mit deinem Konto abgeglichen.":
        "Your breaks are stored on this device and synced with your account.",
    "Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.": "Your session has expired. Please sign in again.",
    "Der Beginn darf nicht in der Zukunft liegen.": "The start can't be in the future.",
    "Der Link ist abgelaufen oder wurde auf einem anderen Gerät angefordert.":
        "The link has expired or was requested on another device.",
    "Die Passwörter stimmen nicht überein.": "The passwords don't match.",
    "Die Pause von %@ wird endgültig entfernt.": "The break from %@ will be removed permanently.",
    "Die Pause wird endgültig entfernt.": "The break will be removed permanently.",
    "Die Pause überschneidet sich mit einer anderen Pause.": "The break overlaps with another break.",
    "Die Sprache der App wählst du in den iOS-Einstellungen von BreakTimer.":
        "You choose the app's language in BreakTimer's page in iOS Settings.",
    "Dunkel": "Dark",
    "Durchschnitt": "Average",
    "E-Mail": "Email",
    "E-Mail erneut senden": "Resend Email",
    "E-Mail oder Passwort ist falsch.": "Incorrect email or password.",
    "E-Mail wurde erneut gesendet.": "Email sent again.",
    "E-Mail-Adresse": "Email Address",
    "Einstellungen": "Settings",
    "Ende": "End",
    "Erinnerungen während einer laufenden Pause.": "Reminders while a break is running.",
    "Erneut senden (%lld s)": "Resend (%lld s)",
    "Erscheinungsbild": "Appearance",
    "Etwas ist schiefgelaufen. Bitte versuche es erneut.": "Something went wrong. Please try again.",
    "Falls es ein Konto für %@ gibt, haben wir dir einen Link zum Zurücksetzen geschickt. Öffne ihn auf diesem iPhone.":
        "If there's an account for %@, we've sent you a reset link. Open it on this iPhone.",
    "Fertig": "Done",
    "Für diese E-Mail-Adresse gibt es bereits ein Konto.": "There's already an account for this email address.",
    "Gib deine E-Mail-Adresse ein. Wir schicken dir einen Link, mit dem du ein neues Passwort festlegen kannst.":
        "Enter your email address. We'll send you a link to set a new password.",
    "Gilt sofort für heute, auch für eine laufende Pause, und für alle folgenden Tage.":
        "Applies right away to today, including a running break, and to all following days.",
    "Hallo BreakTimer-Support,\n\nbitte beschreibe hier kurz dein Problem:\n– Was hast du gemacht?\n– Was ist passiert?\n– Was hast du stattdessen erwartet?\n\n\n\nDas Protokoll ist angehängt. Es enthält technische Daten und Pausenzeiten, aber keine Passwörter.":
        "Hello BreakTimer Support,\n\nplease briefly describe your problem here:\n– What did you do?\n– What happened?\n– What did you expect instead?\n\n\n\nThe log is attached. It contains technical data and break times, but no passwords.",
    "Hell": "Light",
    "Heute": "Today",
    "Heute genutzt": "Used today",
    "Heutige Pausen": "Today's Breaks",
    "Im Budget": "Within budget",
    "Jetzt synchronisieren": "Sync Now",
    "Keine Pausen an diesem Tag.": "No breaks on this day.",
    "Keine Verbindung zum Server. Bitte prüfe deine Internetverbindung.":
        "Can't reach the server. Please check your internet connection.",
    "Konto": "Account",
    "Konto endgültig löschen?": "Delete account permanently?",
    "Konto erstellen": "Create Account",
    "Konto löschen": "Delete Account",
    "Kopieren": "Copy",
    "Kopiert": "Copied",
    "Lege ein neues Passwort für dein Konto fest.": "Set a new password for your account.",
    "Link senden": "Send Link",
    "LÖSCHEN": "DELETE",
    "Löschen": "Delete",
    "Melde dich in BreakTimer an.": "Sign in to BreakTimer.",
    "Min.": "min",
    "Mindestens %lld Zeichen.": "At least %lld characters.",
    "Minuten": "Minutes",
    "Mitteilungen": "Notifications",
    "Modus": "Mode",
    "Nach der Registrierung bekommst du eine E-Mail, um deine Adresse zu bestätigen.":
        "After signing up, you'll get an email to confirm your address.",
    "Neues Passwort": "New Password",
    "Nicht angemeldet": "Not signed in",
    "Noch 5 Minuten Pause": "5 minutes of break left",
    "Noch keine Pausen heute.": "No breaks yet today.",
    "Noch nicht synchronisiert": "Not synced yet",
    "Noch nie": "Never",
    "Passwort": "Password",
    "Passwort anzeigen": "Show password",
    "Passwort speichern": "Save Password",
    "Passwort verbergen": "Hide password",
    "Passwort vergessen?": "Forgot Password?",
    "Passwort wiederholen": "Repeat Password",
    "Passwort zurücksetzen": "Reset Password",
    "Passwort ändern": "Change Password",
    "Pause bearbeiten": "Edit Break",
    "Pause beenden": "End Break",
    "Pause läuft": "Break running",
    "Pause läuft noch": "Break is still running",
    "Pause löschen": "Delete Break",
    "Pause löschen?": "Delete break?",
    "Pause starten": "Start Break",
    "Pause vergessen zu beenden?": "Forgot to end your break?",
    "Pause zu dieser Zeit beenden": "End Break at This Time",
    "Pause · %@ über": "Break · %@ over",
    "Pause · %@ übrig": "Break · %@ left",
    "Pausen": "Breaks",
    "Pausen pro Tag": "Breaks per day",
    "Pausen vom %@": "Breaks on %@",
    "Pausenbudget": "Break Budget",
    "Pausenbudget aufgebraucht": "Break budget used up",
    "Pausenbudget überzogen": "Break budget exceeded",
    "Protokoll an Support senden": "Send Log to Support",
    "Protokoll löschen": "Delete Log",
    "Protokoll löschen?": "Delete log?",
    "Protokoll senden": "Send Log",
    "Protokoll teilen": "Share Log",
    "Protokollgröße": "Log Size",
    "Quelle": "Source",
    "Registrieren": "Sign Up",
    "Sichern": "Save",
    "Sprache": "Language",
    "Starten": "Start",
    "Startet eine Pause und zieht sie vom Tagesbudget ab.": "Starts a break and counts it against the daily budget.",
    "Supabase ist nicht konfiguriert. Trage URL und Anon Key in Config.xcconfig ein.":
        "Supabase isn't configured. Enter the URL and anon key in Config.xcconfig.",
    "Support-Adresse": "Support Address",
    "Synchronisierung": "Sync",
    "Tag": "Day",
    "Tage": "Days",
    "Tatsächliches Ende": "Actual end",
    "Tägliches Pausenbudget": "Daily Break Budget",
    "Verbleibende Pausenzeit auf dem Sperrbildschirm.": "Remaining break time on the Lock Screen.",
    "Verbleibende Pausenzeit mit Taste zum Starten und Beenden.": "Remaining break time with a button to start and end breaks.",
    "Verlauf": "History",
    "Wenn das Budget aufgebraucht ist": "When the budget is used up",
    "Wir haben einen Link an %@ geschickt. Öffne ihn auf diesem iPhone, um dein Konto zu aktivieren.":
        "We've sent a link to %@. Open it on this iPhone to activate your account.",
    "Wähle ein neues Passwort mit mindestens 8 Zeichen.": "Choose a new password with at least 8 characters.",
    "Zeitraum": "Period",
    "Zu viele Versuche. Bitte warte einen Moment.": "Too many attempts. Please wait a moment.",
    "Zuletzt synchronisiert": "Last Synced",
    "Zum Bearbeiten tippen, zum Löschen wischen.": "Tap to edit, swipe to delete.",
    "Zurück zur Anmeldung": "Back to Sign In",
    "läuft noch": "still running",
    "Öffnet die Einstellungen von BreakTimer in der App „Einstellungen“.": "Opens BreakTimer's page in the Settings app.",
    "Über": "Over",
    "Über Budget": "Over budget",
    "Überzogen": "Over budget",
    "Übrig": "Left",
    "über": "over",
    "übrig": "left",
}

# Keys whose wording depends on a count: (German one, German other, English one, English other).
PLURALS = {
    "%lld Änderungen sind noch nicht synchronisiert und gehen beim Abmelden verloren. Alle Pausen und Einstellungen werden von diesem iPhone entfernt.": (
        "%lld Änderung ist noch nicht synchronisiert und geht beim Abmelden verloren. Alle Pausen und Einstellungen werden von diesem iPhone entfernt.",
        "%lld Änderungen sind noch nicht synchronisiert und gehen beim Abmelden verloren. Alle Pausen und Einstellungen werden von diesem iPhone entfernt.",
        "%lld change hasn't been synced yet and will be lost when you sign out. All breaks and settings will be removed from this iPhone.",
        "%lld changes haven't been synced yet and will be lost when you sign out. All breaks and settings will be removed from this iPhone.",
    ),
}


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def plural(one, other):
    return {"variations": {"plural": {"one": unit(one), "other": unit(other)}}}


def extracted_keys(target):
    keys = set()
    for path in glob.glob(f"{BUILD}/{target}.build/Objects-normal/arm64/*.stringsdata"):
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        for item in data.get("tables", {}).get("Localizable", []):
            keys.add(item["key"])
    return keys


def main():
    missing_translations = set()
    for target, catalog_path in TARGETS.items():
        keys = extracted_keys(target)
        if not keys:
            sys.exit(f"No extracted strings for {target}. Build the project first.")
        with open(catalog_path, encoding="utf-8") as handle:
            catalog = json.load(handle)
        strings = catalog.setdefault("strings", {})
        added = 0
        for key in sorted(keys):
            if key in strings and key in DO_NOT_TRANSLATE:
                continue
            existing = strings.get(key, {}).get("localizations", {})
            if existing:
                # Explicit German values make Xcode emit de.lproj, so iOS keeps German as an
                # available language for this bundle even though the keys are already German.
                if "de" not in existing and key not in PLURALS:
                    existing["de"] = unit(key)
                continue
            entry = {}
            if key in DO_NOT_TRANSLATE:
                entry["shouldTranslate"] = False
            elif key in PLURALS:
                de_one, de_other, en_one, en_other = PLURALS[key]
                entry["localizations"] = {"de": plural(de_one, de_other), "en": plural(en_one, en_other)}
            elif key in EN:
                entry["localizations"] = {"de": unit(key), "en": unit(EN[key])}
            else:
                missing_translations.add(key)
            strings[key] = entry
            added += 1
        catalog["sourceLanguage"] = "de"
        catalog["version"] = "1.0"
        with open(catalog_path, "w", encoding="utf-8") as handle:
            json.dump(catalog, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        print(f"{target}: {len(keys)} keys, {added} added")
    for key in sorted(missing_translations):
        print(f"  no English translation: {key!r}")


if __name__ == "__main__":
    main()
