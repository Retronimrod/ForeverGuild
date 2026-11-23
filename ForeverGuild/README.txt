ForeverGuild 0.9.33 · WoW Forever 1.60.1

Installation
1. Den Ordner ForeverGuild aus der ZIP nach Interface/AddOns kopieren.
2. Einloggen oder /reload ausführen.
3. Jeden eigenen Herstellungsberuf einmal öffnen.
4. Mit /fguild die Übersicht öffnen. Über die Suche nach Charakter,
   Beruf oder Rezept filtern. Bei leerer Suche werden alle Daten gezeigt.

Gildenabgleich
Ein weiteres Gildenmitglied installiert diese Version und öffnet seine
Herstellungsberufe. Der Abgleich startet beim Einloggen. Über „Gilde
abgleichen“ lässt er sich erneut anstoßen. Antworten können durch die
zeitversetzte Übertragung größerer Rezeptlisten etwas dauern.

Jeder Client sendet nur die eigenen Berufsdaten. Bereits empfangene
Profile bleiben nach normalem Logout oder /reload sichtbar. Für den
ersten Empfang müssen Sender und Empfänger gleichzeitig online sein.
Datum und Uhrzeit zeigen den Zeitpunkt des letzten Empfangs.

Diese Alpha wurde lokal getestet. Der Test mit zwei echten Clients
auf Riverlands steht noch aus.

Übersicht
Links stehen die Berufe und Rezepte des
gewählten Charakters. Rechts steht die Gildenliste. Ein Klick auf eine
Berufskarte klappt die Rezepte auf. Die Suche filtert beide Seiten. Rezeptzeilen
zeigen beim Darüberfahren den Rezepttooltip sowie das Ergebnisitem,
wenn der Client dafür einen Link liefert. Der Log-Tab zeigt
Abgleichanfragen, gesendete und empfangene Berufsdaten.

Automatische Erfassung und Abgleich
Mit /fguild scan on aktivierst du den optionalen Hintergrundscan.
ForeverGuild versucht dann kurz nach der Anmeldung, die bekannten
Herstellungsberufe nacheinander im Hintergrund zu öffnen und zu
erfassen. Ein bereits geöffnetes Berufefenster hat Vorrang.
Wenn der Client das automatische Öffnen nicht zulässt, den Beruf
einmal normal öffnen. Der Abgleich läuft auch bei geschlossenem
ForeverGuild-Fenster in Abständen von rund fünf Minuten.

Diagnose und Navigation
Die letzten 400 Diagnoseereignisse bleiben lokal pro Charakter
gespeichert. /fguild debug, Rechtsklick auf das Minimap-Symbol oder
„Diagnose exportieren“ im Log öffnet die kopierbare Textansicht.
Linksklick auf das Minimap-Symbol öffnet die Übersicht. Am rechten
Fensterrand liegen Berufe, Log und Gildenroster.
Die Skill-Skalen reichen bei allen Berufen von 0 bis 300.

Gildenroster
Der Seitenreiter zeigt Name, Klasse, Stufe, Gildenrang, Rollen und
Onlinestatus. Über die Spaltenköpfe sortieren, per Suchfeld filtern.
Im Profil rechts stehen Zone oder letzte Aktivität, Berufe und Abgleich.
Die eigenen Rollen pro Charakter lassen sich frei kombinieren und
werden mit ForeverGuild ab Version 0.6.0 in der Gilde abgeglichen.

Rollen und Skillung
Mitglieder bearbeiten den gerade eingeloggten eigenen Charakter.
Gildenmeister (Rangindex 0) und die Ränge „Offizier“ oder „Officer“
können Rollen und Skillung fremder Mitglieder bearbeiten. Empfänger
prüfen den Absender anhand ihrer Gildenliste. Für diese Funktionen
benötigen die Beteiligten ForeverGuild 0.6.1 oder neuer.

Charakter einrichten
Der Dialog erscheint beim ersten Gildenlogin mit dieser Version,
wenn für den Charakter weder Rolle noch Skillung eingetragen ist.
Über das Zahnrad und „Charakter einrichten“ oder /fguild setup
lässt sich der Dialog manuell öffnen.
„Berufe erfassen“ zeigt Schaltflächen für bekannte Herstellungsberufe.
Klicke jeden Beruf einzeln an und starte danach den Gildenabgleich.
Die Roster-Tabelle zeigt auch die synchronisierte Skillung.

Einstellungen
Das Zahnrad oder /fguild settings öffnet Allgemein, Gildenabgleich
und Info und Diagnose. Der regelmäßige Abgleich ist standardmäßig an.
Der manuelle Abgleich steht im Einstellungsfenster.

Gildenverwaltung
Im neuen Seitenreiter lassen sich Gildennachricht und Mitgliedsnotizen
einsehen. Die Bearbeitung setzt das entsprechende WoW-Recht voraus.
Offiziersnotizen werden erst bei vorhandenem Leserecht angezeigt.
Für Rangverwaltung und eingeschränkte Aktionen öffnet der Reiter
das originale WoW-Gildenfenster.

Handwerksaufträge
Rechtsklick auf ein Rezept, „In Auftrag geben“, Anzahl der
Herstellungen auswählen und „Auftrag senden“ klicken. Der direkte
Empfang funktioniert ab ForeverGuild 0.9.1. Die Zutatenliste
dient zur Übersicht. Erledigte Aufträge lassen sich markieren.
„Meine Aufträge“ enthält empfangene Aufträge. „Gesendete Aufträge“
zeigt eigene Aufträge mit der Empfangsbestätigung des Handwerkers.
Beide Listen zeigen Zeitstempel, Beruf und Rezept. Die Rezeptfarbe
folgt der Seltenheit des Ergebnisitems. „Anflüstern“ öffnet den Chat
mit dem Auftraggeber oder Handwerker.
Seit 0.9.5 können aktualisierte Gildenclients Offline-Aufträge
zwischenlagern und weiterleiten. Mindestens ein solcher Client muss
den Auftrag mitbekommen und später gleichzeitig mit dem Handwerker
online sein. Ein bestätigter Auftrag wird aus dem Zwischenspeicher
entfernt. War ein Client beim Empfang offline, wird seine Kopie
bei einer späteren Bestätigung oder beim Ablauf der Aufbewahrung
von 14 Tagen bereinigt.
„Nur erledigte“ zeigt das Archiv. Wiedereröffnete Aufträge wechseln
in die offene Liste und tragen den Status „Wiedereröffnet“.

Ein Briefsymbol an der Minimap zeigt ungelesene Handwerksaufträge.
Ein Klick öffnet den neuesten ungelesenen Auftrag. Weitere bleiben
markiert, bis du sie auswählst. Die Markierung bleibt beim Reload
erhalten. Doppelt empfangene Nachrichten lösen keinen neuen Hinweis aus.

Sobald der Handwerker einen Auftrag als erledigt markiert, erhält
der Auftraggeber eine Chatmeldung und einen Hinweis an der Minimap.
Sind nicht beide online, bleibt die Statusmeldung bis zum nächsten
gemeinsamen Login vorgemerkt. Beide benötigen mindestens Version 0.9.14.

Gildenbank / Guild bank: Open the in-game guild bank to scan viewable tabs and automatically share their contents with the guild. Request shared snapshots from online guild members in the Guild Bank tab.
