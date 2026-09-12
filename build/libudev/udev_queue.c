/*
 * udev_queue - la parte de libudev que libudev-zero no trae.
 *
 * SPDX-License-Identifier: ISC
 * Escrito para MIKE OS. Se compila dentro de libudev-zero (ISC), del que
 * este archivo es una pieza más; ver scripts/build.sh.
 *
 * ---------------------------------------------------------------------------
 * Por qué existe
 *
 * MIKE OS no lleva systemd, así que tampoco lleva su libudev: en su lugar va
 * libudev-zero, que implementa la parte de la API que hace falta para que el
 * escritorio funcione. Lo que NO implementa es la familia udev_queue_*,
 * porque describe la cola de trabajo de un demonio udev que aquí no existe.
 *
 * El problema es que libdevmapper -- y por debajo de ella parted, y por
 * debajo GParted -- pide exactamente tres de esos símbolos al enlazarse:
 *
 *     udev_new                        (libudev-zero sí lo tiene)
 *     udev_queue_new                  (falta)
 *     udev_queue_unref                (falta)
 *     udev_queue_get_udev_is_active   (falta)
 *     udev_unref                      (libudev-zero sí lo tiene)
 *
 * Sin ellos, parted arranca y muere en el acto:
 *
 *     parted: symbol lookup error: /usr/lib/libdevmapper.so.1.02:
 *             undefined symbol: udev_queue_unref, version LIBUDEV_183
 *
 * y con parted caído se cae con él todo lo que lo usa por debajo, GParted
 * incluido. Tres funciones de diez líneas son lo único que separa a MIKE OS
 * de poder usar las herramientas de particionado de siempre.
 *
 * ---------------------------------------------------------------------------
 * Qué contestan, y por qué esa respuesta es la CORRECTA y no un apaño
 *
 * udev_queue_get_udev_is_active() devuelve 0: no hay demonio udev.
 *
 * Eso no es mentir para salir del paso: es la verdad, y además es la
 * respuesta que hace que libdevmapper se comporte bien. Al ver que no hay
 * udev, deja de esperar a que alguien le cree los nodos de dispositivo y los
 * gestiona ella misma, que es justo lo que hay que hacer en un sistema sin
 * udev. Si mintiéramos diciendo que sí lo hay, libdevmapper se quedaría
 * esperando eternamente a una cola que nadie va a vaciar.
 *
 * udev_queue_get_queue_is_empty() devuelve 1 por lo mismo: una cola que no
 * existe no tiene nada pendiente, así que quien pregunte "¿puedo seguir?"
 * debe oír que sí.
 *
 * Las funciones que devuelven listas devuelven NULL y las de número
 * devuelven 0: no hay nada que enumerar. Están implementadas, aunque
 * libdevmapper no las use, para que cualquier otro programa que se enlace
 * contra libudev encuentre la API entera en vez de caerse por una que falte,
 * que es el fallo que estamos arreglando aquí.
 */

#include <stdlib.h>

#include "udev.h"

struct udev_queue {
    struct udev *udev;
    int refcount;
};

struct udev_queue *udev_queue_new(struct udev *udev)
{
    struct udev_queue *cola;

    if (!udev) {
        return NULL;
    }

    cola = calloc(1, sizeof(*cola));

    if (!cola) {
        return NULL;
    }

    cola->refcount = 1;
    /* Se toma una referencia del udev, como hace la libudev de verdad: quien
     * nos la pasó puede soltarla antes que a nosotros. */
    cola->udev = udev_ref(udev);
    return cola;
}

struct udev_queue *udev_queue_ref(struct udev_queue *cola)
{
    if (!cola) {
        return NULL;
    }

    cola->refcount++;
    return cola;
}

struct udev_queue *udev_queue_unref(struct udev_queue *cola)
{
    if (!cola) {
        return NULL;
    }

    if (--cola->refcount > 0) {
        return cola;
    }

    udev_unref(cola->udev);
    free(cola);
    return NULL;
}

struct udev *udev_queue_get_udev(struct udev_queue *cola)
{
    return cola ? cola->udev : NULL;
}

/* No hay demonio udev. Ver la explicación de arriba: contestar que no es lo
 * que hace que libdevmapper gestione los nodos por su cuenta. */
int udev_queue_get_udev_is_active(struct udev_queue *cola)
{
    (void)cola;
    return 0;
}

/* Una cola que no existe está vacía. */
int udev_queue_get_queue_is_empty(struct udev_queue *cola)
{
    (void)cola;
    return 1;
}

unsigned long long int udev_queue_get_kernel_seqnum(struct udev_queue *cola)
{
    (void)cola;
    return 0;
}

unsigned long long int udev_queue_get_udev_seqnum(struct udev_queue *cola)
{
    (void)cola;
    return 0;
}

int udev_queue_get_seqnum_is_finished(struct udev_queue *cola,
                                      unsigned long long int seqnum)
{
    (void)cola; (void)seqnum;
    return 1;
}

int udev_queue_get_seqnum_sequence_is_finished(struct udev_queue *cola,
                                               unsigned long long int inicio,
                                               unsigned long long int fin)
{
    (void)cola; (void)inicio; (void)fin;
    return 1;
}

struct udev_list_entry *
udev_queue_get_queued_list_entry(struct udev_queue *cola)
{
    (void)cola;
    return NULL;
}

int udev_queue_get_fd(struct udev_queue *cola)
{
    (void)cola;
    return -1;
}

int udev_queue_flush(struct udev_queue *cola)
{
    (void)cola;
    return 0;
}
