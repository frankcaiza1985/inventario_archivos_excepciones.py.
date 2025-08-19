#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sistema de Gestión de Inventarios Mejorado (Con archivos y manejo robusto de excepciones)
-----------------------------------------------------------------------------

Características principales:
- Persistencia en archivo CSV (inventario.txt por defecto, separador ',').
- Carga automática del inventario al iniciar.
- Guardado automático tras añadir/actualizar/eliminar.
- Manejo de excepciones: FileNotFoundError, PermissionError, ValueError
  (corrupción de datos), y una excepción personalizada para errores de archivo.
- Interfaz de usuario por consola con mensajes de éxito y error.
- Registro de incidentes en 'inventario.log' (líneas corruptas, errores, etc.).

Formato del archivo inventario.txt (CSV con encabezados):
    id,nombre,cantidad,precio
    1,Lápiz,100,0.25

Para probar rápidamente: ejecutar este archivo y usar el menú.

Autor: Tu Nombre
Fecha: 2025-08-19
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Optional, Iterable
import csv
import os
import sys
import logging


# ---------------------------- Configuración de logging ----------------------------
LOG_FILE = "inventario.log"
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)


# ---------------------------- Excepciones personalizadas ----------------------------
class ErrorArchivoInventario(Exception):
    """Error general relacionado con operaciones de archivo del inventario."""


class LineaCorruptaError(ErrorArchivoInventario):
    """Representa una línea/registro corrupto o inválido en el archivo CSV."""


# ---------------------------- Modelo de datos ----------------------------
@dataclass
class Producto:
    id: int
    nombre: str
    cantidad: int
    precio: float

    @staticmethod
    def desde_dict(d: Dict[str, str]) -> "Producto":
        """Construye un Producto desde un dict leído por csv.DictReader.

        Puede lanzar ValueError si los tipos no son convertibles.
        """
        return Producto(
            id=int(d["id"]),
            nombre=str(d["nombre"]).strip(),
            cantidad=int(d["cantidad"]),
            precio=float(d["precio"]),
        )

    def to_row(self) -> Dict[str, str]:
        return {
            "id": str(self.id),
            "nombre": self.nombre,
            "cantidad": str(self.cantidad),
            "precio": f"{self.precio:.2f}",
        }


# ---------------------------- Inventario con persistencia ----------------------------
class Inventario:
    ENCABEZADOS = ["id", "nombre", "cantidad", "precio"]

    def __init__(self, ruta_archivo: str = "inventario.txt") -> None:
        self.ruta_archivo = ruta_archivo
        self._items: Dict[int, Producto] = {}
        self._asegurar_archivo()
        self._cargar()

    # ---------- Utilidades privadas ----------
    def _asegurar_archivo(self) -> None:
        """Crea el archivo con encabezados si no existe. Maneja permisos."""
        if not os.path.exists(self.ruta_archivo):
            try:
                with open(self.ruta_archivo, mode="w", encoding="utf-8", newline="") as f:
                    writer = csv.DictWriter(f, fieldnames=self.ENCABEZADOS)
                    writer.writeheader()
                logging.info("Archivo de inventario creado: %s", self.ruta_archivo)
            except PermissionError as e:
                logging.error("Sin permiso para crear archivo: %s", e)
                raise PermissionError(
                    f"No hay permisos para crear el archivo '{self.ruta_archivo}'."
                ) from e

    def _cargar(self) -> None:
        """Carga todos los productos desde el archivo CSV. 

        - Ignora (y registra) líneas corruptas sin detener el programa.
        - Lanza PermissionError si no hay permisos de lectura.
        """
        try:
            with open(self.ruta_archivo, mode="r", encoding="utf-8", newline="") as f:
                reader = csv.DictReader(f)
                if reader.fieldnames is None:
                    raise LineaCorruptaError("El archivo no contiene encabezados válidos.")

                for idx, row in enumerate(reader, start=2):  # empieza en 2 (1=encabezado)
                    try:
                        prod = Producto.desde_dict(row)
                        self._items[prod.id] = prod
                    except (ValueError, KeyError) as e:
                        logging.warning(
                            "Línea %d corrupta en %s: %s | row=%s",
                            idx,
                            self.ruta_archivo,
                            e,
                            row,
                        )
                        # Se continúa sin interrumpir la carga
        except FileNotFoundError:
            # En teoría no debería ocurrir por _asegurar_archivo, pero se maneja igual
            logging.warning("Archivo no encontrado al cargar. Se creará uno nuevo.")
            self._asegurar_archivo()
        except PermissionError as e:
            logging.error("Sin permisos de lectura: %s", e)
            raise
        except OSError as e:
            # Otros errores de E/S (disco lleno, etc.)
            logging.error("Error de E/S al cargar: %s", e)
            raise ErrorArchivoInventario("Error de E/S al cargar el inventario.") from e

    def _guardar_todo(self) -> None:
        """Escribe todo el inventario al archivo CSV, con manejo de errores.

        Lanza PermissionError si no hay permisos de escritura.
        """
        try:
            tmp_path = self.ruta_archivo + ".tmp"
            with open(tmp_path, mode="w", encoding="utf-8", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=self.ENCABEZADOS)
                writer.writeheader()
                for prod in self._items.values():
                    writer.writerow(prod.to_row())
            # Reemplazo atómico cuando es posible
            os.replace(tmp_path, self.ruta_archivo)
        except PermissionError as e:
            logging.error("Sin permisos de escritura: %s", e)
            raise
        except OSError as e:
            logging.error("Error de E/S al guardar: %s", e)
            raise ErrorArchivoInventario("Error de E/S al guardar el inventario.") from e

    # ---------- Operaciones públicas ----------
    def listar(self) -> Iterable[Producto]:
        return sorted(self._items.values(), key=lambda p: p.id)

    def obtener(self, id_: int) -> Optional[Producto]:
        return self._items.get(id_)

    def agregar(self, prod: Producto) -> None:
        if prod.id in self._items:
            raise ValueError(f"Ya existe un producto con id {prod.id}.")
        self._items[prod.id] = prod
        self._guardar_todo()

    def actualizar(self, id_: int, *, nombre: Optional[str] = None,
                   cantidad: Optional[int] = None, precio: Optional[float] = None) -> None:
        prod = self._items.get(id_)
        if not prod:
            raise KeyError(f"No existe producto con id {id_}.")
        if nombre is not None:
            prod.nombre = nombre
        if cantidad is not None:
            if cantidad < 0:
                raise ValueError("La cantidad no puede ser negativa.")
            prod.cantidad = cantidad
        if precio is not None:
            if precio < 0:
                raise ValueError("El precio no puede ser negativo.")
            prod.precio = precio
        self._guardar_todo()

    def eliminar(self, id_: int) -> None:
        if id_ not in self._items:
            raise KeyError(f"No existe producto con id {id_}.")
        del self._items[id_]
        self._guardar_todo()


# ---------------------------- Interfaz de usuario por consola ----------------------------

def pedir_int(mensaje: str) -> int:
    while True:
        try:
            return int(input(mensaje).strip())
        except ValueError:
            print("❌ Entrada inválida. Debe ser un número entero.")


def pedir_float(mensaje: str) -> float:
    while True:
        try:
            return float(input(mensaje).strip().replace(",", "."))
        except ValueError:
            print("❌ Entrada inválida. Debe ser un número (usa punto decimal).")


def imprimir_productos(inv: Inventario) -> None:
    print("\n=== INVENTARIO ACTUAL ===")
    print(f"{'ID':<6}{'NOMBRE':<20}{'CANT':>8}{'PRECIO':>12}")
    print("-" * 48)
    for p in inv.listar():
        print(f"{p.id:<6}{p.nombre:<20}{p.cantidad:>8}{p.precio:>12.2f}")
    print("-" * 48)


def menu():
    inv = None
    try:
        inv = Inventario()  # Carga automática desde el archivo
        print("✅ Inventario cargado correctamente desde 'inventario.txt'.")
        print(f"ℹ️  Revisa el log en '{LOG_FILE}' si deseas más detalles.")
    except PermissionError:
        print("❌ No se pudo leer o crear 'inventario.txt' por falta de permisos.")
        print("   - Ejecuta con permisos adecuados o elige otra ruta.")
        return
    except ErrorArchivoInventario as e:
        print(f"⚠️  Se produjo un error de archivo: {e}")
        return

    while True:
        print(
            """
\n===== MENÚ INVENTARIO =====
1) Listar productos
2) Añadir producto
3) Actualizar producto
4) Eliminar producto
5) Buscar producto por ID
6) Cambiar ruta de archivo (avanzado)
0) Salir
            """
        )
        opcion = input("Elige una opción: ").strip()

        if opcion == "1":
            imprimir_productos(inv)

        elif opcion == "2":
            try:
                id_ = pedir_int("ID: ")
                nombre = input("Nombre: ").strip()
                cantidad = pedir_int("Cantidad: ")
                precio = pedir_float("Precio: ")
                inv.agregar(Producto(id_, nombre, cantidad, precio))
                print("✅ Producto añadido y guardado en archivo correctamente.")
            except ValueError as e:
                print(f"❌ Error de validación: {e}")
            except PermissionError:
                print("❌ No se pudo escribir en el archivo (permiso denegado).")
            except ErrorArchivoInventario as e:
                print(f"⚠️  Error de archivo: {e}")

        elif opcion == "3":
            try:
                id_ = pedir_int("ID del producto a actualizar: ")
                print("Deja vacío el campo que no quieras cambiar.")
                nombre = input("Nuevo nombre: ").strip()
                cantidad_txt = input("Nueva cantidad: ").strip()
                precio_txt = input("Nuevo precio: ").strip()

                kwargs = {}
                if nombre:
                    kwargs["nombre"] = nombre
                if cantidad_txt:
                    kwargs["cantidad"] = int(cantidad_txt)
                if precio_txt:
                    kwargs["precio"] = float(precio_txt.replace(",", "."))

                inv.actualizar(id_, **kwargs)
                print("✅ Producto actualizado y cambios guardados en archivo.")
            except KeyError as e:
                print(f"❌ {e}")
            except ValueError as e:
                print(f"❌ Error de validación: {e}")
            except PermissionError:
                print("❌ No se pudo escribir en el archivo (permiso denegado).")
            except ErrorArchivoInventario as e:
                print(f"⚠️  Error de archivo: {e}")

        elif opcion == "4":
            try:
                id_ = pedir_int("ID a eliminar: ")
                inv.eliminar(id_)
                print("✅ Producto eliminado y archivo actualizado.")
            except KeyError as e:
                print(f"❌ {e}")
            except PermissionError:
                print("❌ No se pudo escribir en el archivo (permiso denegado).")
            except ErrorArchivoInventario as e:
                print(f"⚠️  Error de archivo: {e}")

        elif opcion == "5":
            id_ = pedir_int("ID a buscar: ")
            p = inv.obtener(id_)
            if p:
                print(f"Encontrado → ID:{p.id} | Nombre:{p.nombre} | Cant:{p.cantidad} | Precio:{p.precio:.2f}")
            else:
                print("ℹ️  No se encontró un producto con ese ID.")

        elif opcion == "6":
            nueva_ruta = input("Nueva ruta de archivo (por ejemplo C:/temp/inventario.csv): ").strip()
            if not nueva_ruta:
                print("ℹ️  Ruta no cambiada.")
                continue
            try:
                inv.ruta_archivo = nueva_ruta
                inv._asegurar_archivo()
                inv._guardar_todo()
                print(f"✅ Ruta cambiada y datos guardados en '{nueva_ruta}'.")
            except PermissionError:
                print("❌ Permiso denegado al cambiar/guardar en la nueva ruta.")
            except ErrorArchivoInventario as e:
                print(f"⚠️  Error de archivo: {e}")

        elif opcion == "0":
            print("👋 ¡Hasta luego!")
            break
        else:
            print("❌ Opción no válida. Intenta de nuevo.")


# ---------------------------- Pruebas rápidas (opcional) ----------------------------
# Estas pruebas no sustituyen unitaria formales, pero ayudan a verificar
# comportamiento básico, incluidas algunas rutas de error.

def _pruebas_basicas():
    print("\n[PRUEBAS] Iniciando pruebas básicas...")
    ruta_prueba = "inventario_pruebas.txt"
    if os.path.exists(ruta_prueba):
        os.remove(ruta_prueba)
    inv = Inventario(ruta_prueba)
    assert len(list(inv.listar())) == 0

    # Agregar
    inv.agregar(Producto(1, "Lápiz", 100, 0.25))
    inv.agregar(Producto(2, "Cuaderno", 50, 1.75))
    assert inv.obtener(1) is not None and inv.obtener(2) is not None

    # Actualizar
    inv.actualizar(1, cantidad=120)
    assert inv.obtener(1).cantidad == 120

    # Eliminar
    inv.eliminar(2)
    assert inv.obtener(2) is None

    # Recarga desde disco
    inv2 = Inventario(ruta_prueba)
    assert inv2.obtener(1) is not None and inv2.obtener(2) is None

    print("[PRUEBAS] OK ✅")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--test":
        _pruebas_basicas()
    else:
        menu()
