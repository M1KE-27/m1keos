import QtQuick

// Iconos de MIKE OS, dibujados a trazo.
//
// Antes los iconos eran caracteres de texto: ◆ ◐ ⌥ ⓘ ⚙, y los del volumen
// emojis (🔊 🔉 🔇). Dos problemas. Uno, que el emoji no tiene glifo en la
// fuente del sistema y salía un cuadrado vacío en la barra. Y dos, que un
// símbolo Unicode suelto no es un icono: no comparte grosor, ni tamaño, ni
// rejilla con los de al lado, así que la barra nunca llega a verse de una
// pieza.
//
// Se dibujan sobre una rejilla de 24x24 y se escalan al tamaño pedido, con
// un grosor de trazo proporcional. Canvas y nada más: ni fuentes de iconos,
// ni SVG, ni plugins de imagen que puedan no estar en la imagen final.
Canvas {
    id: icono

    property string nombre: ""
    property color color: Paleta.texto
    property int tamano: 14
    // Relleno para los iconos que lo piden (el punto del espacio activo).
    property bool relleno: false

    implicitWidth: tamano
    implicitHeight: tamano
    width: tamano
    height: tamano
    antialiasing: true

    onNombreChanged: requestPaint()
    onColorChanged: requestPaint()
    onRellenoChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var k = width / 24          // de la rejilla de 24 al tamaño real
        ctx.scale(k, k)
        ctx.strokeStyle = icono.color
        ctx.fillStyle = icono.color
        ctx.lineWidth = 2
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        dibujar(ctx, icono.nombre)
    }

    // --- Ayudas de trazo ------------------------------------------------
    function linea(ctx, x1, y1, x2, y2) {
        ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
    }
    function caja(ctx, x, y, w, h, r) {
        ctx.beginPath()
        ctx.moveTo(x + r, y)
        ctx.lineTo(x + w - r, y);      ctx.quadraticCurveTo(x + w, y, x + w, y + r)
        ctx.lineTo(x + w, y + h - r);  ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
        ctx.lineTo(x + r, y + h);      ctx.quadraticCurveTo(x, y + h, x, y + h - r)
        ctx.lineTo(x, y + r);          ctx.quadraticCurveTo(x, y, x + r, y)
        ctx.closePath(); ctx.stroke()
    }
    function circulo(ctx, cx, cy, r, lleno) {
        ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2)
        if (lleno) ctx.fill(); else ctx.stroke()
    }
    function arco(ctx, cx, cy, r, desde, hasta) {
        ctx.beginPath(); ctx.arc(cx, cy, r, desde, hasta); ctx.stroke()
    }

    // --- El catálogo ----------------------------------------------------
    function dibujar(ctx, n) {
        switch (n) {

        // Altavoz: el cuerpo es el mismo en los tres estados y sólo cambian
        // las ondas, para que pasar de 30 % a 80 % no parezca otro icono.
        case "volumen-mudo":
        case "volumen-bajo":
        case "volumen-alto":
            ctx.beginPath()
            ctx.moveTo(4, 9); ctx.lineTo(7, 9); ctx.lineTo(11, 5)
            ctx.lineTo(11, 19); ctx.lineTo(7, 15); ctx.lineTo(4, 15)
            ctx.closePath(); ctx.stroke()
            if (n === "volumen-mudo") {
                linea(ctx, 15, 9.5, 20, 14.5)
                linea(ctx, 20, 9.5, 15, 14.5)
            } else {
                arco(ctx, 11, 12, 4.5, -Math.PI / 3, Math.PI / 3)
                if (n === "volumen-alto")
                    arco(ctx, 11, 12, 8, -Math.PI / 3, Math.PI / 3)
            }
            return

        // Red por cable: dos nodos y el cable entre ellos.
        case "cable":
            caja(ctx, 3, 4, 18, 6, 1.5)
            caja(ctx, 3, 14, 18, 6, 1.5)
            linea(ctx, 12, 10, 12, 14)
            return

        // WiFi: tres arcos y el punto.
        case "wifi":
            arco(ctx, 12, 17, 9.5, Math.PI * 1.2, Math.PI * 1.8)
            arco(ctx, 12, 17, 6, Math.PI * 1.2, Math.PI * 1.8)
            circulo(ctx, 12, 17, 1.4, true)
            return

        case "sin-red":
            arco(ctx, 12, 17, 9.5, Math.PI * 1.2, Math.PI * 1.8)
            linea(ctx, 5, 19, 19, 5)
            return

        case "bluetooth":
            ctx.beginPath()
            ctx.moveTo(7, 8); ctx.lineTo(17, 16); ctx.lineTo(12, 20)
            ctx.lineTo(12, 4); ctx.lineTo(17, 8); ctx.lineTo(7, 16)
            ctx.stroke()
            return

        case "reloj":
            circulo(ctx, 12, 12, 8.5, false)
            linea(ctx, 12, 7, 12, 12)
            linea(ctx, 12, 12, 15.5, 14)
            return

        // Medidores: un indicador de aguja, que es lo que son.
        case "medidores":
            arco(ctx, 12, 15, 8, Math.PI, Math.PI * 2)
            linea(ctx, 12, 15, 16.5, 10.5)
            return

        // Ajustes: deslizadores, no un engranaje. El engranaje dice
        // "configuración de motor"; los deslizadores dicen "aquí se regula".
        case "ajustes":
            linea(ctx, 4, 7, 20, 7)
            linea(ctx, 4, 17, 20, 17)
            circulo(ctx, 9, 7, 2.6, false)
            circulo(ctx, 16, 17, 2.6, false)
            return

        case "teclado":
            caja(ctx, 2.5, 6, 19, 12, 2)
            linea(ctx, 6, 10, 6.2, 10)
            linea(ctx, 10, 10, 10.2, 10)
            linea(ctx, 14, 10, 14.2, 10)
            linea(ctx, 18, 10, 18.2, 10)
            linea(ctx, 8, 14, 16, 14)
            return

        case "captura":
            caja(ctx, 2.5, 6.5, 19, 13, 2.5)
            circulo(ctx, 12, 13, 3.8, false)
            linea(ctx, 8.5, 6.5, 10, 4)
            linea(ctx, 15.5, 6.5, 14, 4)
            return

        case "cerrar":
            linea(ctx, 6.5, 6.5, 17.5, 17.5)
            linea(ctx, 17.5, 6.5, 6.5, 17.5)
            return

        case "buscar":
            circulo(ctx, 10.5, 10.5, 6.5, false)
            linea(ctx, 15.5, 15.5, 20, 20)
            return

        case "info":
            circulo(ctx, 12, 12, 8.5, false)
            linea(ctx, 12, 11, 12, 16.5)
            circulo(ctx, 12, 7.8, 1.1, true)
            return

        case "editar":
            ctx.beginPath()
            ctx.moveTo(4, 20); ctx.lineTo(4, 16); ctx.lineTo(16, 4)
            ctx.lineTo(20, 8); ctx.lineTo(8, 20); ctx.closePath(); ctx.stroke()
            return

        // Marca de MIKE OS: el cursor de una terminal. Es lo que es el
        // sistema, y no otro rombo genérico más.
        case "logo":
            ctx.beginPath()
            ctx.moveTo(5, 6); ctx.lineTo(11, 12); ctx.lineTo(5, 18); ctx.stroke()
            linea(ctx, 13, 18, 20, 18)
            return

        // --- Apartados del Centro de Control ---
        case "vistazo":
            arco(ctx, 12, 15, 8, Math.PI, Math.PI * 2)
            linea(ctx, 12, 15, 15, 10)
            return
        case "sistema":
            caja(ctx, 7, 7, 10, 10, 1.5)
            linea(ctx, 10, 3.5, 10, 7);   linea(ctx, 14, 3.5, 14, 7)
            linea(ctx, 10, 17, 10, 20.5); linea(ctx, 14, 17, 14, 20.5)
            linea(ctx, 3.5, 10, 7, 10);   linea(ctx, 3.5, 14, 7, 14)
            linea(ctx, 17, 10, 20.5, 10); linea(ctx, 17, 14, 20.5, 14)
            return
        case "barra":
            caja(ctx, 3, 4, 18, 4.5, 1.5)
            caja(ctx, 3, 12, 18, 8, 1.5)
            return
        case "escritorio":
            caja(ctx, 2.5, 4.5, 19, 13, 2)
            linea(ctx, 8, 20, 16, 20)
            return
        case "interfaz":
            ctx.beginPath()
            ctx.moveTo(12, 3.5); ctx.lineTo(21, 8.5); ctx.lineTo(12, 13.5)
            ctx.lineTo(3, 8.5); ctx.closePath(); ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(3, 14); ctx.lineTo(12, 19); ctx.lineTo(21, 14); ctx.stroke()
            return
        case "servicios":
            circulo(ctx, 12, 12, 3, false)
            linea(ctx, 12, 3, 12, 6);   linea(ctx, 12, 18, 12, 21)
            linea(ctx, 3, 12, 6, 12);   linea(ctx, 18, 12, 21, 12)
            return
        case "avanzado":
            caja(ctx, 2.5, 4.5, 19, 15, 2)
            ctx.beginPath()
            ctx.moveTo(6.5, 9.5); ctx.lineTo(9.5, 12); ctx.lineTo(6.5, 14.5); ctx.stroke()
            linea(ctx, 12, 15, 17, 15)
            return

        // --- Flechas y marcas del editor de la barra ---
        case "izquierda":
            ctx.beginPath(); ctx.moveTo(14.5, 6); ctx.lineTo(8.5, 12)
            ctx.lineTo(14.5, 18); ctx.stroke(); return
        case "derecha":
            ctx.beginPath(); ctx.moveTo(9.5, 6); ctx.lineTo(15.5, 12)
            ctx.lineTo(9.5, 18); ctx.stroke(); return
        case "abajo":
            ctx.beginPath(); ctx.moveTo(6, 9.5); ctx.lineTo(12, 15.5)
            ctx.lineTo(18, 9.5); ctx.stroke(); return
        case "mas":
            linea(ctx, 12, 5, 12, 19); linea(ctx, 5, 12, 19, 12); return
        case "menos":
            linea(ctx, 5, 12, 19, 12); return
        case "check":
            ctx.beginPath(); ctx.moveTo(5, 12.5); ctx.lineTo(10, 17.5)
            ctx.lineTo(19, 7); ctx.stroke(); return

        // Punto del espacio de trabajo.
        case "punto":
            circulo(ctx, 12, 12, icono.relleno ? 6 : 4.5, icono.relleno)
            return
        }
    }
}
