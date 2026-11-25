ForeverGuild 0.9.51 · WoW Forever 1.60.1

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

Schwarzes Brett (ab 0.9.34)
Beim Rezept „In Auftrag geben“ öffnen, Menge und Materialstellung
wählen, optional eine Notiz eintragen und „Ans Schwarze Brett hängen“
klicken. Der eigene Seitenreiter zeigt aktive Aufträge, „Meine
Aufträge“ und den Verlauf. Alle Beteiligten brauchen 0.9.34 oder neuer.

Der Client des Auftraggebers bestätigt die erste gültige Annahme
und synchronisiert den zugewiesenen Handwerker mit der Gilde.
Bis zur Bestätigung bleibt die Annahme ausstehend. Auftraggeber
und Handwerker müssen sich dafür online überschneiden. Das gilt
auch für „Fertig zur Übergabe“ und die Freigabe. Ein Auftrag am
Brett wird beim nächsten Abgleich sichtbar, wenn der Auftraggeber
online ist. Bereits empfangene Einträge werden lokal gespeichert.

Der Handwerker markiert den Auftrag als bereit oder gibt ihn wieder
frei. Der Besteller bestätigt nach dem Handel „Erhalten“. Abgeschlossene
und zurückgezogene Aufträge stehen im Verlauf. Persönliche Aufträge
werden wie bisher separat angezeigt.


Rezeptkatalog und Laufzeit (ab 0.9.35)
Schwarzes Brett → Neuen Auftrag aufgeben öffnet den Rezeptkatalog.
Links nach Beruf filtern, rechts nach Rezeptname, verfügbarem
Ergebnisnamen oder Rezept-ID suchen. Die eingebauten Rezeptdaten
werden um eigene und synchronisierte Gildenrezepte ergänzt. Ein
bekannter Handwerker ist zum Erstellen nicht erforderlich.

Die Laufzeit beträgt 1 bis 30 Tage (Vorgabe: 7). Offene Aufträge
wandern nach Ablauf in den Verlauf. Bereits zugewiesene Aufträge
können nach Fristablauf abgeschlossen werden. Gibt der Handwerker
einen solchen Auftrag nach Fristablauf frei, wird er nicht erneut
zur Annahme angeboten. Neue Aufträge mit Laufzeit erscheinen ab
0.9.35. Bereits vorhandene Brettaufträge behalten ihren Status und
ihre bisherige Laufzeit (unbefristet).

Rezept- und Itemdaten (ab 0.9.36)
Der Rezeptkatalog enthält die Herstellungsrezepte aus LibProfessionDB
1.10.1 für WoW Forever 1.60.1.70938 (MIT, siehe Lizenzdatei).
Nicht implementierte Einträge und Berufsrangbücher werden ausgefiltert.
Deutsch und Englisch sind als Namensreserve enthalten. Fehlende
Rezepte aus dem geöffneten Berufsfenster werden lokal ergänzt, ebenso
bleiben synchronisierte Gildenrezepte über den Katalog erreichbar.
Fehlende Zutaten werden nach Möglichkeit aus dem Katalog angezeigt,
wenn die Spiel-API für das Rezept keine Zutaten bereitstellt.

Beim Login und durch /reload beginnt im Hintergrund das Laden von
Ergebnisitems und Zutaten. Die Items bestehender Aufträge kommen zuerst.
Antworten des WoW-Clients werden asynchron übernommen.

Mitteilungen und Gruppenzettel (ab 0.9.37)
Am Schwarzen Brett gibt es neben Handwerksaufträgen die Bereiche
Mitteilungen und Gruppenzettel. Oben steht die aktuelle Gildennachricht
aus WoW. Gildenmeister und Offiziere können zusätzliche Mitteilungen
anheften. Diese bleiben bis zu 30 Tage sichtbar.

Ein Gruppenzettel besteht aus Titel, Details und einem Starttermin
in deiner Ortszeit. Empfänger sehen den Termin in ihrer Ortszeit.
Gildenmitglieder können zusagen oder ihre Zusage zurückziehen.
Der Organisator kann seinen Zettel jederzeit abnehmen. Zum
Starttermin verschwinden Gruppenzettel vom Brett. Für den Abgleich
brauchen die Beteiligten 0.9.37 oder neuer. Eigene Zettel und Zusagen
werden wiederholt gesendet, solange der jeweilige Absender online ist.

Im Rezeptkatalog sind eingebettete Rezeptnamen direkt sichtbar.
Erfolgreich geladene Itemdaten bleiben über /reload und Relog
erhalten. Der Ladebalken zeigt fehlende WoW-Itemdaten; die Rezeptliste
kann schon während des Nachladens bedient werden.

Rezeptwähler (ab 0.9.39)
Die Spalte „Kategorien“ filtert zusätzlich zum Beruf, etwa nach
Leder, Kette oder Platte. Die Zeile zeigt das Rezept. Beim
Darüberfahren öffnet sich der Rezepttooltip. Bei neuen Aufträgen
ist „Ich stelle die Materialien“ standardmäßig angehakt.

Gruppenzettel (ab 0.9.45)
Die Aktivitätsauswahl zeigt Zone und Stufenempfehlung bzw. PvP-Stufe.
Die Zusammensetzung ist frei einstellbar, standardmäßig 1 Tank,
1 Heiler und 3 DD. Der Organisator belegt einen Platz seiner Rolle.
Teilnehmer wählen ihre Rolle bei der Zusage. Ist diese Rolle voll,
rücken wartende Teilnehmer bei einer Absage nach ihrer Anmeldezeit
nach. Für rollenbasierte Zusagen brauchen die Beteiligten 0.9.45.

Dungeonbanner (ab 0.9.48)
Jeder der 28 Dungeons hat eigenes Banner-Artwork im
Aktivitätswähler und auf dem Gruppenzettel. Bilddateien enthalten
keine Schrift. Name, Zone und Stufe werden im Addon in Deutsch
oder Englisch angezeigt (Englisch als Fallback). Eigene Titel
und Notizen werden im Wortlaut angezeigt.
