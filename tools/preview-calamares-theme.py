#!/usr/bin/env python3
"""Look at the installer theme without building an ISO.

    tools/preview-calamares-theme.py [FAMILY/VARIANT] [OUT_DIR]
        [--scale S] [--font app|dyslexic] [--fonts-dir DIR] [--screen WxH]

Resolves the Calamares branding templates for the given palette (default
stellar_blade/lily) the way iso/build.sh does, applies the stylesheet to the
widgets the installer actually uses, and writes OUT_DIR/gallery.png (default
iso/out/theme-preview/), then the slideshow in each language,
OUT_DIR/slideshow-en.png and slideshow-fr.png. Offscreen - needs pyside6, not a
display. Hover states are not rendered offscreen; everything else is.

The boot entry's choices are reproduced the way the live session applies them:
--scale is colony.textscale, set as QT_SCALE_FACTOR on a screen of --screen
device pixels (default 1280x800), so the images show what fits at that size;
--font is colony.font, through the same fontconfig file the installer reads,
with the font files taken from --fonts-dir (default /usr/share/fonts/colony,
where colony-fonts installs them). Check the design system's extremes,
--scale 0.7225 and --scale 1.68, after a layout or text change.

The sidebar's four colours come from branding.desc, not the stylesheet, so the
preview paints them itself from the same palette fields branding.desc.in names.
"""
import argparse, json, os, shutil, subprocess, sys, tempfile

ROOT = os.path.realpath(os.path.join(os.path.dirname(os.path.realpath(__file__)), ".."))
AIROOTFS = os.path.join(ROOT, "iso/install/airootfs")
BRANDING = os.path.join(AIROOTFS, "etc/calamares/branding/colony")
RESOURCES = os.environ.get("COLONY_RESOURCES", os.path.join(ROOT, "..", "Project-Colony-Resources"))
themes = os.path.join(RESOURCES, "generated", "themes.json")

ap = argparse.ArgumentParser()
ap.add_argument("spec", nargs="?", default="stellar_blade/lily")
ap.add_argument("out", nargs="?", default=os.path.join(ROOT, "iso/out/theme-preview"))
ap.add_argument("--scale", type=float, default=1.0)
ap.add_argument("--font", choices=("app", "dyslexic"), default="app")
ap.add_argument("--fonts-dir", default="/usr/share/fonts/colony")
ap.add_argument("--screen", default="1280x800")
args = ap.parse_args()
spec, out = args.spec, args.out
fam, var = spec.split("/")
screen_w, screen_h = map(int, args.screen.split("x"))

# The live session's environment, not this desktop's: no platform theme, whose
# own font would win over fontconfig's, and the boot entry's font and scale.
bdir = tempfile.mkdtemp(prefix="colony-branding-")
fonts_conf = os.path.join(bdir, "fonts.conf")
with open(fonts_conf, "w") as f:
    f.write(f'''<?xml version="1.0"?>
<fontconfig>
  <dir>{args.fonts_dir}</dir>
  <cachedir>{os.path.join(bdir, "fontconfig-cache")}</cachedir>
  <include ignore_missing="no">{os.path.join(AIROOTFS, "usr/share/colony/fontconfig", args.font + ".conf")}</include>
</fontconfig>
''')
os.environ["FONTCONFIG_FILE"] = fonts_conf
os.environ.pop("QT_QPA_PLATFORMTHEME", None)
os.environ["QT_QPA_PLATFORM"] = "offscreen"
os.environ["QT_SCALE_FACTOR"] = str(args.scale)

from PySide6 import QtCore, QtGui, QtWidgets, QtQuick, QtQuickWidgets

warnings = []
QtCore.qInstallMessageHandler(lambda mode, ctx, msg: warnings.append(msg))

shutil.copytree(BRANDING, bdir, dirs_exist_ok=True)
subprocess.run([sys.executable, os.path.join(ROOT, "tools/resolve-theme.py"), themes, spec,
                *[os.path.join(bdir, f) for f in os.listdir(bdir) if f.endswith(".in")]],
               check=True, stdout=subprocess.DEVNULL)
os.makedirs(out, exist_ok=True)
qss = open(os.path.join(bdir, "stylesheet.qss")).read()
pal = next(v["palette"] for f in json.load(open(themes))["families"] if f["key"] == fam
           for v in f["variants"] if v["key"] == var)

# Calamares' slideshow is a QQuickWidget; offscreen, it renders in software.
QtQuick.QQuickWindow.setGraphicsApi(QtQuick.QSGRendererInterface.GraphicsApi.Software)
app = QtWidgets.QApplication([])
app.setStyle("Fusion")
app.setStyleSheet(qss)

# The installer fills the screen (cage), so at a text scale it has the screen's
# device pixels divided by the scale to lay itself out in.
root = QtWidgets.QWidget(); root.setObjectName("mainApp")
root.resize(round(screen_w / args.scale), round(screen_h / args.scale))
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
font = QtGui.QFontInfo(app.font()).family()
root.close()

# The slideshow, in the content area beside the step list, in each language.
# calamares.slideshow is replaced by a stub that only lays slides out: the real
# module needs Calamares to load it.
stub = os.path.join(bdir, "qml", "calamares", "slideshow")
os.makedirs(stub)
with open(os.path.join(stub, "qmldir"), "w") as f:
    f.write("module calamares.slideshow\nPresentation 1.0 Presentation.qml\nSlide 1.0 Slide.qml\n")
with open(os.path.join(stub, "Presentation.qml"), "w") as f:
    f.write("import QtQuick 2.0\nItem { }\n")
with open(os.path.join(stub, "Slide.qml"), "w") as f:
    f.write("import QtQuick 2.0\nItem { anchors.fill: parent }\n")
for lang in ("en", "fr"):
    # What Calamares' Qt.locale() reports: the boot language, through LANG.
    QtCore.QLocale.setDefault(QtCore.QLocale(lang))
    view = QtQuickWidgets.QQuickWidget()
    view.engine().addImportPath(os.path.join(bdir, "qml"))
    view.setResizeMode(QtQuickWidgets.QQuickWidget.SizeRootObjectToView)
    # Sized from the screen, not from the gallery, which packs more widgets
    # than any one page and outgrows a small screen at a large scale.
    view.resize(round(screen_w / args.scale) - side.width(), round(screen_h / args.scale) - 120)
    view.setSource(QtCore.QUrl.fromLocalFile(os.path.join(bdir, "show.qml")))
    view.show(); app.processEvents()
    view.grab().save(os.path.join(out, f"slideshow-{lang}.png"))
    view.close()

shutil.rmtree(bdir)
print(f"{out}/{{gallery,slideshow-en,slideshow-fr}}.png  ({spec}, scale {args.scale}, "
      f"{font}, {len(warnings)} Qt warning(s))")
for w in warnings:
    print("  ", w)
