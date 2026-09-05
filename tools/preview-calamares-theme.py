#!/usr/bin/env python3
"""Look at the installer theme without building an ISO.

    tools/preview-calamares-theme.py [FAMILY/VARIANT] [OUT_DIR]

Resolves the Calamares branding templates for the given palette (default
stellar_blade/lily) the way iso/build.sh does, applies the stylesheet to the
widgets the installer actually uses, and writes OUT_DIR/gallery.png (default
iso/out/theme-preview/). Offscreen — needs pyside6, not a display. Hover states
are not rendered offscreen; everything else is.

The sidebar's four colours come from branding.desc, not the stylesheet, so the
preview paints them itself from the same palette fields branding.desc.in names.
"""
import json, os, shutil, subprocess, sys, tempfile
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6 import QtCore, QtGui, QtWidgets

ROOT = os.path.realpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), ".."))
BRANDING = os.path.join(ROOT, "iso/install/airootfs/etc/calamares/branding/colony")
RESOURCES = os.environ.get("COLONY_RESOURCES", os.path.join(ROOT, "..", "Project-Colony-Resources"))
themes = os.path.join(RESOURCES, "generated", "themes.json")
spec = sys.argv[1] if len(sys.argv) > 1 else "stellar_blade/lily"
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "iso/out/theme-preview")
fam, var = spec.split("/")

warnings = []
QtCore.qInstallMessageHandler(lambda mode, ctx, msg: warnings.append(msg))

bdir = tempfile.mkdtemp(prefix="colony-branding-")
shutil.copytree(BRANDING, bdir, dirs_exist_ok=True)
subprocess.run([sys.executable, os.path.join(ROOT, "tools/resolve-theme.py"), themes, spec,
                *[os.path.join(bdir, f) for f in os.listdir(bdir) if f.endswith(".in")]],
               check=True, stdout=subprocess.DEVNULL)
os.makedirs(out, exist_ok=True)
qss = open(os.path.join(bdir, "stylesheet.qss")).read()
pal = next(v["palette"] for f in json.load(open(themes))["families"] if f["key"] == fam
           for v in f["variants"] if v["key"] == var)

app = QtWidgets.QApplication([])
app.setStyle("Fusion")
app.setStyleSheet(qss)

root = QtWidgets.QWidget(); root.setObjectName("mainApp"); root.resize(1000, 660)
h = QtWidgets.QHBoxLayout(root); h.setContentsMargins(0, 0, 0, 0); h.setSpacing(0)

# sidebar: colours come from branding.desc, mimicked here for the preview only
side = QtWidgets.QFrame(); side.setObjectName("sidebarApp"); side.setFixedWidth(190)
sv = QtWidgets.QVBoxLayout(side); sv.setContentsMargins(0, 16, 0, 16); sv.setSpacing(0)
logo = QtWidgets.QLabel(); logo.setObjectName("logoApp")
logo.setPixmap(QtGui.QPixmap(os.path.join(bdir, "logo.png")).scaled(72, 72, QtCore.Qt.KeepAspectRatio, QtCore.Qt.SmoothTransformation))
logo.setAlignment(QtCore.Qt.AlignCenter); sv.addWidget(logo); sv.addSpacing(16)
for i, step in enumerate(["Bienvenue", "Emplacement", "Clavier", "Partitions", "Paquets", "Utilisateurs", "Résumé", "Installation", "Terminer"]):
    l = QtWidgets.QLabel("   " + step); l.setFixedHeight(30)
    if i == 4:
        l.setStyleSheet(f"background-color:{pal['accent_blue']};color:{pal['bg_primary']};font-weight:bold")
    else:
        l.setStyleSheet(f"background-color:{pal['bg_sidebar']};color:{pal['text_secondary']}")
    sv.addWidget(l)
sv.addStretch(); h.addWidget(side)

main = QtWidgets.QWidget(); v = QtWidgets.QVBoxLayout(main); v.setContentsMargins(20, 16, 20, 12); v.setSpacing(10)
h.addWidget(main, 1)
t = QtWidgets.QLabel("Paquets"); t.setObjectName("summaryTitle"); f = t.font(); f.setPointSize(14); t.setFont(f); v.addWidget(t)
e = QtWidgets.QLabel("Choisissez les groupes à installer. Un groupe partiellement coché apparaît en demi-teinte."); e.setObjectName("resultsExplanation"); e.setWordWrap(True); v.addWidget(e)

row = QtWidgets.QHBoxLayout()
le = QtWidgets.QLineEdit(); le.setPlaceholderText("Nom de la machine…"); row.addWidget(le)
cb = QtWidgets.QComboBox(); cb.addItems(["Europe/Paris", "Europe/Bruxelles", "America/Montréal"]); row.addWidget(cb)
sp = QtWidgets.QSpinBox(); sp.setRange(1, 64); sp.setValue(8); sp.setSuffix(" GiB"); row.addWidget(sp)
led = QtWidgets.QLineEdit("désactivé"); led.setEnabled(False); row.addWidget(led)
v.addLayout(row)

row2 = QtWidgets.QHBoxLayout()
c1 = QtWidgets.QCheckBox("Non coché"); c2 = QtWidgets.QCheckBox("Coché"); c2.setChecked(True)
c3 = QtWidgets.QCheckBox("Partiel"); c3.setTristate(True); c3.setCheckState(QtCore.Qt.PartiallyChecked)
c4 = QtWidgets.QCheckBox("Désactivé"); c4.setEnabled(False)
r1 = QtWidgets.QRadioButton("Effacer le disque"); r1.setChecked(True); r2 = QtWidgets.QRadioButton("Manuel")
for w in (c1, c2, c3, c4, r1, r2): row2.addWidget(w)
row2.addStretch(); v.addLayout(row2)

split = QtWidgets.QHBoxLayout(); split.setSpacing(12)
tree = QtWidgets.QTreeView(); tree.setAlternatingRowColors(True)
model = QtGui.QStandardItemModel(); model.setHorizontalHeaderLabels(["Groupe", "Description"])
def item(name, desc, state):
    a = QtGui.QStandardItem(name); a.setCheckable(True); a.setCheckState(state)
    return a, QtGui.QStandardItem(desc)
groups = [("Écran de connexion", "Un seul, obligatoire", QtCore.Qt.PartiallyChecked, ["sddm", "gdm", "ly", "greetd", "lightdm"]),
          ("Bureaux", "Cocher plusieurs est permis", QtCore.Qt.Checked, ["cosmic", "hyprland", "plasma", "gnome"]),
          ("Colony", "Les programmes de l'écosystème", QtCore.Qt.Checked, ["paru"]),
          ("Multimédia", "", QtCore.Qt.Unchecked, ["pipewire", "mpv", "vlc", "obs-studio", "kdenlive"] + [f"paquet-{i}" for i in range(40)])]
for name, desc, state, kids in groups:
    a, b = item(name, desc, state); model.appendRow([a, b])
    for i, k in enumerate(kids):
        ka, kb = item(k, "", QtCore.Qt.Checked if (state == QtCore.Qt.Checked or (state == QtCore.Qt.PartiallyChecked and i == 0)) else QtCore.Qt.Unchecked)
        a.appendRow([ka, kb])
tree.setModel(model); tree.expandAll(); tree.setColumnWidth(0, 220)
tree.setCurrentIndex(model.index(0, 0).child(0, 0) if hasattr(model.index(0,0), "child") else model.index(1, 0))
tree.selectionModel().select(model.indexFromItem(model.item(1)), QtCore.QItemSelectionModel.Select | QtCore.QItemSelectionModel.Rows)
split.addWidget(tree, 3)

right = QtWidgets.QVBoxLayout(); right.setSpacing(10)
gb = QtWidgets.QGroupBox("Chiffrement"); gv = QtWidgets.QVBoxLayout(gb)
gv.addWidget(QtWidgets.QCheckBox("Chiffrer le système")); gv.addWidget(QtWidgets.QLineEdit("••••••••"))
right.addWidget(gb)
tabs = QtWidgets.QTabWidget(); tabs.addTab(QtWidgets.QLabel("  Contenu de l'onglet"), "Résumé"); tabs.addTab(QtWidgets.QWidget(), "Détails"); tabs.setFixedHeight(90)
right.addWidget(tabs)
te = QtWidgets.QTextEdit(); te.setPlainText("Journal : chargement des paquets…\n[colony] colonyctl 0.1-2\n[colony] colony-firewall-control 0.2.2-1"); te.setFixedHeight(80)
right.addWidget(te)
sl = QtWidgets.QSlider(QtCore.Qt.Horizontal); sl.setValue(60); right.addWidget(sl)
right.addStretch(); split.addLayout(right, 2)
v.addLayout(split, 1)

pb = QtWidgets.QProgressBar(); pb.setObjectName("exec-progress"); pb.setValue(42); pb.setFormat("Installation : %p%"); v.addWidget(pb)
msg = QtWidgets.QLabel("Installation des paquets (611 / 1453)"); msg.setObjectName("exec-message"); v.addWidget(msg)

nav = QtWidgets.QHBoxLayout()
ab = QtWidgets.QPushButton("À propos"); ab.setObjectName("aboutButton"); nav.addWidget(ab)
dis = QtWidgets.QPushButton("Désactivé"); dis.setEnabled(False); nav.addWidget(dis)
nav.addStretch()
cancel = QtWidgets.QPushButton("Annuler"); cancel.setObjectName("view-button-cancel"); nav.addWidget(cancel)
back = QtWidgets.QPushButton("Précédent"); back.setObjectName("view-button-back"); nav.addWidget(back)
nxt = QtWidgets.QPushButton("Suivant"); nxt.setObjectName("view-button-next"); nav.addWidget(nxt)
v.addLayout(nav)

root.show(); app.processEvents()
root.grab().save(os.path.join(out, "gallery.png"))
shutil.rmtree(bdir)
print(f"{os.path.join(out, 'gallery.png')}  ({spec}, {len(warnings)} Qt warning(s))")
for w in warnings:
    print("  ", w)
