import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Slide {
        Image {
            id: logo
            source: "logo.png"
            width: 160; height: 160
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }

        Text {
            anchors.horizontalCenter: logo.horizontalCenter
            anchors.top: logo.bottom
            anchors.topMargin: 28
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            width: presentation.width * 0.75
            text: "<b>Arch Colony</b><br/><br/>" +
                  "Arch Linux — mêmes dépôts, mêmes miroirs, même rythme de mise à jour.<br/>" +
                  "Plus une couche : noyau durci, pare-feu applicatif, " +
                  "et les programmes de l'écosystème Colony."
        }
    }
}
