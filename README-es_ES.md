# Rootless-DevBox (con carpeta de caché de nix específica/externa)

Una solución simple y automatizada para instalar Devbox en un entorno sin root, sin requerir privilegios de sudo o root. Versión original de: https://github.com/nebstudio/Rootless-DevBox.

**Información del Fork:**
Este fork de https://github.com/twoelz añade varias mejoras para soportar instalaciones en almacenamiento externo y mejorar la experiencia general de instalación. Las adiciones clave incluyen:

**Características principales:**
1. **Ubicación personalizada del almacén Nix**: Prompt interactivo para instalar el almacén Nix en almacenamiento externo (ej., `/sgoinfre` en 42 school) en lugar de `~/.nix` fijo
2. **Enlace simbólico inteligente de caché**: Solo enlaza la caché al almacenamiento externo, mantiene la base de datos crítica local
3. **Soporte multi-shell**: Configura bash, zsh y fish (el original solo soportaba bash)
4. **Mirrors de red de China**: Mirrors opcionales SJTU/Tsinghua para usuarios en China continental
5. **Función auto-chroot**: Entrada automática opcional a nix-chroot al iniciar shell
6. **Desinstalador mejorado**: Detecta ubicaciones de instalación personalizadas y elimina todos los componentes de forma segura

A continuación se presenta una descripción detallada del enfoque de enlaces simbólicos:

Al instalar Nix en una ubicación personalizada (por ejemplo, almacenamiento externo), el instalador crea un enlace simbólico para el directorio de caché de Nix:

~/.cache/nix → <ubicación-personalizada>/cache/nix

**Por qué solo caché (no datos/base de datos):**

- Directorio de caché: Grande (GBs), regenerable, seguro de limpiar → va al almacenamiento externo
- Directorio de datos: Pequeño (~MBs), contiene base de datos SQLite crítica → permanece local para confiabilidad y rendimiento

**Beneficios:**

- Ahorro de espacio: La caché de descarga de Nix (mayor consumidor fuera del almacén) vive en almacenamiento externo
- Consistencia: Tanto comandos Nix globales como nix-chroot usan la misma caché, evitando duplicación
- Aislamiento: Solo la caché de Nix se redirige; otras aplicaciones continúan usando ~/.cache normalmente
- Confiabilidad: La base de datos crítica permanece en almacenamiento local rápido y confiable (~/.local/share/nix)
- Compatible con Nix: El almacén Nix mismo (~/.nix o ubicación personalizada) permanece como un directorio real (no un enlace simbólico)

**Comportamiento:**

- Instalación predeterminada (~/.nix): No se crean enlaces simbólicos, usa ubicaciones XDG estándar
- Instalación personalizada: Crea enlace simbólico de caché, respalda cualquier directorio ~/.cache/nix existente
- Base de datos/estado permanece en ~/.local/share/nix por seguridad

Este enfoque evita configurar variables globales XDG_CACHE_HOME y XDG_DATA_HOME que afectarían todas las aplicaciones en todo el sistema.

**Configuración de Shell:**
El instalador añade configuración a tus archivos dotfiles de shell (bash/zsh/fish). Esta configuración:
- Añade `~/.local/bin` y `~/.nix-profile/bin` a PATH (para ejecutar comandos devbox/nix)
- Incluye la configuración de entorno propia de Nix
- NO establece variables XDG globalmente (la redirección de caché usa enlaces simbólicos en su lugar)

[![GitHub License](https://img.shields.io/github/license/nebstudio/Rootless-DevBox)](https://github.com/nebstudio/Rootless-DevBox/blob/main/LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/nebstudio/Rootless-DevBox?style=social)](https://github.com/nebstudio/Rootless-DevBox/stargazers)
[![GitHub Issues](https://img.shields.io/github/issues/nebstudio/Rootless-DevBox)](https://github.com/nebstudio/Rootless-DevBox/issues)

## ¿Qué es Rootless-DevBox (con carpetas específicas de nix)?

Rootless-DevBox es un proyecto que permite a los usuarios instalar y usar [Devbox](https://github.com/jetify-com/devbox) en entornos donde no tienen acceso root, como hosting compartido, sistemas universitarios o entornos corporativos con permisos restringidos. Utiliza [nix-user-chroot](https://github.com/nix-community/nix-user-chroot) para crear un entorno contenido donde Nix y Devbox pueden ejecutarse sin requerir privilegios elevados.

## Características

- 🛡️ **No requiere root**: Instala y usa Devbox sin sudo ni root
- 🔄 **Entorno aislado**: Ejecuta paquetes en un entorno contenido sin afectar el sistema
- 🚀 **Instalación fácil**: Un solo script para configurar todo automáticamente
- 💻 **Multiplataforma**: Funciona en varias distribuciones y arquitecturas de Linux
- 🔒 **Seguro**: Solo modifica tu entorno de usuario, no los archivos del sistema
- 🌏 **Compatible con redes de China**: El script puede configurar automáticamente Nix para usar mirrors de la Universidad Tsinghua para usuarios en China continental u otros entornos con redes restringidas

> **Nota:**  
> Aunque el script intenta minimizar problemas de red añadiendo el mirror Nix de Tsinghua para usuarios en China continental o redes restringidas, es posible que **aún necesites usar temporalmente un proxy** para acceder a recursos en GitHub u otros sitios que estén bloqueados o limitados en tu región.

## Inicio rápido

> **Nota:**  
> El script de instalación es intencionadamente interactivo y te pedirá confirmaciones en varios pasos.  
> Esto está diseñado así para que puedas tomar decisiones durante la instalación, entender cada paso y adaptar el proceso a tu entorno.  
> No te desanimes por los mensajes adicionales: este enfoque maximiza la compatibilidad y el control del usuario, especialmente en entornos Linux diversos o restringidos.

Simplemente ejecuta este comando en tu terminal:

```bash
# Descarga el instalador
curl -o rootless-devbox-installer.sh https://raw.githubusercontent.com/nebstudio/Rootless-DevBox/main/install.sh

# Hazlo ejecutable
chmod +x rootless-devbox-installer.sh

# Ejecuta el instalador
./rootless-devbox-installer.sh
```

## ¿Cómo funciona?

Rootless-DevBox (con carpetas configuradas) configura tu entorno en 4 pasos principales:

0. Ejecuta un script para configurar carpetas/directorios de nix en una dirección separada

1. **Instala nix-user-chroot**: Descarga y configura una herramienta que crea un entorno chroot en espacio de usuario
2. **Crea el entorno Nix**: Configura un entorno Nix aislado en tu directorio de usuario
3. **Instala Devbox**: Instala Devbox dentro de este entorno para que puedas usarlo sin root

Después de la instalación, accederás a tu entorno de desarrollo usando el comando `nix-chroot`, que activa el entorno aislado donde Devbox está disponible.

## Uso

### Entrar al entorno Nix

Después de la instalación, entra al entorno Nix ejecutando:

```bash
nix-chroot
```

Verás que tu prompt cambia para indicar que estás en el entorno nix-chroot:

```
(nix-chroot) usuario@host:~$
```

### Usar Devbox

Dentro del entorno nix-chroot, puedes usar Devbox normalmente:

```bash
# Mostrar ayuda
devbox help

# Inicializar un nuevo proyecto
devbox init

# Agregar paquetes
devbox add nodejs python

# Iniciar un shell con tu entorno de desarrollo
devbox shell
```

### Salir del entorno

Para salir del entorno nix-chroot:

```bash
exit
```

## Requisitos

- Sistema operativo basado en Linux
- Shell Bash
- Conexión a Internet
- ¡No se necesita acceso root!

## Arquitecturas soportadas

- x86_64
- aarch64/arm64
- armv7
- i686/i386

## Solución de problemas

### Problemas comunes

**P: Me sale "command not found" al intentar usar nix-chroot.**  
R: Asegúrate de que `~/.local/bin` esté en tu PATH. Prueba ejecutando `source ~/.bashrc` o reinicia tu terminal.

**P: La instalación falla al descargar nix-user-chroot.**  
R: Verifica tu conexión a Internet. Si el problema persiste, intenta descargar el binario adecuado manualmente desde [la página de releases](https://github.com/nix-community/nix-user-chroot/releases).

**P: No puedo instalar paquetes en el entorno Nix.**  
R: Algunos sistemas tienen cuotas o limitaciones de espacio en disco. Verifica tu espacio disponible con `df -h ~`.

Para más ayuda, por favor [abre un issue](https://github.com/nebstudio/Rootless-DevBox/issues).

## Desinstalación

Si necesitas eliminar Rootless-DevBox de tu sistema, tienes dos opciones:

### Opción 1: Usar el script de desinstalación

Proveemos un script para eliminar la mayoría de los componentes:

```bash
# Descarga el desinstalador
curl -o rootless-devbox-uninstaller.sh https://raw.githubusercontent.com/nebstudio/Rootless-DevBox/main/uninstall.sh

# Hazlo ejecutable
chmod +x rootless-devbox-uninstaller.sh

# Ejecuta el desinstalador
./rootless-devbox-uninstaller.sh
```

### Opción 2: Desinstalación manual (recomendada)

Para mayor control, puedes eliminar los componentes manualmente:

1. **Elimina los binarios instalados**:
   ```bash
   rm -f ~/.local/bin/devbox
   rm -f ~/.local/bin/nix-chroot
   rm -f ~/.local/bin/nix-user-chroot
   ```

2. **Limpia el directorio de Nix** (opcional, elimina todos los paquetes de Nix):
   ```bash
   rm -rf ~/.nix
   ```

3. **⚠️ IMPORTANTE: Edita tu archivo de configuración de shell** (`~/.bashrc`, `~/.zshrc`, etc.):

   **Muy recomendado**: Revisa y elimina manualmente las siguientes líneas en vez de depender de una limpieza automática:
   
   - Elimina la línea de modificación de PATH:
     ```bash
     export PATH="$HOME/.local/bin:$PATH" # Added by Rootless-DevBox
     ```
   
   - Elimina el bloque de modificación de PS1:
     ```bash
     # Rootless-DevBox nix-chroot environment indicator
     if [ "$NIX_CHROOT" = "1" ]; then
       PS1="(nix-chroot) \[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "
     fi
     ```

   Después de editar, aplica los cambios:
   ```bash
   source ~/.bashrc  # o tu archivo de configuración de shell específico
   ```

> **Nota**: Aunque el script de desinstalación intenta editar tu archivo de configuración de shell de forma segura, **revisar y eliminar manualmente las líneas específicas** es lo más seguro para evitar modificaciones no deseadas.

Después de desinstalar, puede que necesites abrir una nueva sesión de terminal para que todos los cambios tengan efecto.

## Contribuir

¡Las contribuciones son bienvenidas! No dudes en enviar un Pull Request.

1. Haz un fork del repositorio
2. Crea una rama de funcionalidad: `git checkout -b feature/mi-funcionalidad`
3. Haz tus cambios: `git commit -m 'Agrega mi funcionalidad'`
4. Sube la rama: `git push origin feature/mi-funcionalidad`
5. Abre un Pull Request

## Agradecimientos

Este proyecto no sería posible sin estos increíbles proyectos:

- [nix-user-chroot](https://github.com/nix-community/nix-user-chroot) - Permite ejecutar Nix como usuario sin root
- [Devbox](https://github.com/jetify-com/devbox) - Excelente herramienta de entorno de desarrollo
- [Nix](https://nixos.org/) - El potente sistema de gestión de paquetes subyacente

## Licencia

Este proyecto está licenciado bajo la licencia MIT - consulta el archivo [LICENSE](LICENSE) para más detalles.

## Consideraciones de seguridad

Rootless-DevBox solo modifica archivos dentro del directorio home del usuario y no requiere ni usa privilegios de root. Está diseñado para ser seguro incluso en entornos restringidos.

---

⭐ ¡Si este proyecto te ha sido útil, considera darle una estrella en GitHub! ⭐

Creado con ❤️ por [nebstudio](https://github.com/nebstudio)