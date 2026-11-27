ForeverGuild 0.9.65 · WoW Forever 1.60.1

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

Rollen & Rechte (ab 0.9.52)
Gildenverwaltung → Rollen & Rechte.
Der Gildenmeister konfiguriert das Grundprofil und drei zusätzliche
Rollen und weist sie einzelnen Charakteren zu. Die Rechte addieren
sich. Die geprüfte Moderationsaktion „Ausblenden“ speichert den
Moderator, ohne den ursprünglichen Auftrag oder Termin umzuschreiben.
Das betrifft das Schwarze Brett, nicht die persönlichen Direktaufträge.
Die Gilde sollte v0.9.52 gemeinsam verwenden, damit alle Clients
Rollen und ausgeblendete Beiträge berücksichtigen.

Transporttest für Partnergilden
Zwei eingeloggte Charaktere mit v0.9.52 geben jeweils innerhalb von
zwei Minuten /fguild partnertest <Charaktername> für die Gegenseite
ein. Der Chat zeigt, ob Testnachrichten empfangen wurden. Dieser
Test überträgt keine Beiträge und schaltet keine Partnerschaft frei.

Partnergilden (ab 0.9.57)
Unter Gildenverwaltung → Partnergilden kopiert der Gildenmeister
den eigenen Verbindungscode. Beide Seiten fügen den jeweiligen
fremden Code ein und bestätigen Gilde, Realm und Vermittler.
Der Status wechselt nach dem gegenseitigen Nachrichtenabgleich.
Dafür müssen die beiden eingetragenen Vermittler gleichzeitig
online sein. Eine Seite kann die Verbindung jederzeit trennen.
Die Partnerschaft überträgt derzeit keine Inhalte vom Schwarzen Brett.

Neu in 0.9.58
Ausgeblendete Beiträge: /fguild hidden listet sie, /fguild restore <Nummer>
blendet einen Beitrag wieder ein (Moderationsrecht nötig). Alte Einträge
werden nach Ablauf der Beiträge automatisch aufgeräumt.
Das Rechte-Fenster zeigt an, ob Offiziere noch Mitteilungen veröffentlichen
dürfen. Der Gildenmeister kann mit /fguild partnerrelay <Name> einen eigenen
Twink als Vermittler für Partnergilden festlegen; danach braucht die
Partnergilde den neuen Verbindungscode. Ohne Antwort fragt der Vermittler
seltener nach (bis alle 10 Minuten), und „Spieler nicht online“-Meldungen
dafür werden ausgeblendet. Lange stumme Partnerschaften gelten als inaktiv.
Alle Gildenmitglieder sehen die Partnergilden. Bei einem anderen Realm
weist das Fenster darauf hin, dass dies nur bei verbundenen Realms klappt.

Neu in 0.9.65
Beim Aufheben gebundene Gegenstände tauchen in der Auftragssuche nicht mehr
auf und können nicht bestellt werden; geprüft wird der hergestellte
Gegenstand. /fguild bindcheck <Rezept-ID> zeigt die Prüfung an. Die
Einführungstour zeigt jetzt nur das jeweils benötigte Fenster, fängt Klicks
vollständig ab, hat größere Infofenster, eine eigene Station „Gruppe
suchen“ und neue Texte. Neue Symbole für Schwarzes Brett und Gildenbank.

Neu in 0.9.64
Die Einführungstour wurde überarbeitet: blickdichte Infofenster im Stil der
Blizzard-Tutorials, die neben dem jeweils erklärten Bereich erscheinen,
hervorgehobene echte Bedienelemente mit leicht abgedunkeltem Rest,
Fortschrittsbalken und getrennte Schaltflächenreihen.

Neu in 0.9.63
Alte Handwerksaufträge lassen sich wieder verwalten: zurückziehen, erneut
erstellen, archivieren und lokal entfernen. Entfernte Aufträge kommen durch
spätere Synchronisation nicht zurück. Unter Einstellungen → Datenverwaltung
lassen sich abgeschlossene, stornierte und abgelaufene Aufträge gesammelt
bereinigen. Die Rezeptauswahl für Aufträge nutzt jetzt die Gildenberufe-Suche
mit Kategorien, Rüstungsklasse, Attributfiltern (z. B. „Kette Armschienen
Stärke“ oder „lvl>=55 stärke>=10“) und Vergleich mit der getragenen
Ausrüstung. Neu sind außerdem das Einstellungsfenster mit Suche, eine
Einführungstour und eigene Symbole für Gildenbank und Schwarzes Brett.

Neu in 0.9.62
Handwerksmarktplatz: Direkte Aufträge und Aufträge am Schwarzen Brett nutzen
jetzt dieselbe Auftragsverwaltung. Ein angenommener Brett-Auftrag erscheint
automatisch unter Handwerksaufträge. Der neue Auftragsdialog fragt Anzahl,
Materialien pro Gegenstand (was du stellst, was der Handwerker stellt),
Trinkgeld oder feste Vergütung in Gold/Silber/Kupfer (gesamt oder pro
Herstellung), Materialkostenerstattung, Übergabeart, Nachricht, Laufzeit und
Fertigstellungsfrist ab. Die Auftragsverwaltung hat die Registerkarten
Eingegangen, Angenommen, Meine Bestellungen, Bereit zur Übergabe und Verlauf
mit Fortschritt, Übergaben, Zahlungsstatus und Auftragsverlauf. Änderungen
nach der Annahme und Stornierungen brauchen die Zustimmung der anderen Seite.
Zahlungen werden nur dokumentiert; ForeverGuild verwahrt kein Gold.
Benachrichtigungen (Pop-up, Chat, Ton, Zähler, Verlauf) lassen sich unter
Einstellungen → Handwerksmarktplatz pro Art einstellen.

Neu in 0.9.61
Gildenberufe → „Nach Rezepten“ (Standard): gildenweite Rezeptsuche wie im
Auktionshaus. Links Kategorien (Waffen, Rüstung nach Typ und Platz, Schmuck,
Behälter, Verbrauchsgüter, Materialien, Verzauberungen), oben kombinierbare
Filter (Beruf, Platz, Qualität, Stufe, Gegenstandsstufe, Fertigkeit,
Hersteller, Onlinestatus, Bindung). Die Suche versteht mehrere Begriffe und
Synonyme, z. B. „schneider armschienen“ oder „alchi heiltrank“. Jeder
Gegenstand erscheint nur einmal; ein Klick zeigt Rezeptvarianten, Materialien
und alle Hersteller mit „Anflüstern“ und „Beauftragen“. „Nach Handwerkern“
zeigt die bisherige Ansicht. Es zählen nur synchronisierte Rezepte.

Neu in 0.9.60
Schwarzes Brett: Wer einen Auftrag angenommen hat, sieht jetzt wieder
„Bereit zur Übergabe“ und „Freigeben“ (Namen mit Nachnamen wurden nicht
als eigener Charakter erkannt).

Neu in 0.9.59
Schwarzes Brett → „Ausgeblendete Beiträge“: ausgeblendete Beiträge ansehen
und wiederherstellen. Im Rechte-Fenster legt der Gildenmeister fest, welche
Ränge als Offiziere gelten. Unter Partnergilden lässt sich der Vermittler
direkt eintragen. Dungeon-Termine können mit „Auch für Partnergilden“
geteilt werden; sie erscheinen bei der Partnergilde zum Ansehen, Anmeldung
per Flüstern beim Organisator. Die Mitgliederliste zeigt Mitglieder,
Online-Zahl, Gildenmeister, Offiziere und veraltete Addon-Versionen.
