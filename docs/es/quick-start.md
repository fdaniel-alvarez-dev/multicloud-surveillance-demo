# Guía Rápida

Sigue estos pasos para levantar el entorno demo de Multicloud Surveillance en menos de 30 minutos.

## 1. Solicita Acceso
1. Compra el plan de acceso al repositorio o canjea tu código de invitación.
2. Completa el formulario con tu usuario o email de GitHub para habilitar permisos en menos de un día hábil.
3. Descarga el PDF "Start here" desde el correo de confirmación con valores por defecto y FAQs.

## 2. Prepara Tu Sandbox
- Provisiona un clúster de Kubernetes (EKS, AKS o GKE) o usa el script de Kind que incluimos para pruebas locales.
- Garantiza salida a los endpoints de AWS Kinesis, Azure Event Hub y Google Pub/Sub. El demo publica eventos sintéticos en las tres nubes.
- Instala el bundle de CLI: `kubectl`, `helm` y `terraform` v1.5+.

## 3. Despliega el Demo
1. Clona el repositorio y cambia al último tag liberado.
2. Ejecuta `./bootstrap-demo.sh` (incluido en el PDF) para aprovisionar los recursos namespaced y fuentes de streaming de ejemplo.
3. Aplica los manifiestos de dashboards federados descritos en `docs/es/product-story.md` en la sección _Activos para Storytelling_.

## 4. Explora la Experiencia
- **Dashboards:** abre el enlace de Grafana que aparece en la salida del script para revisar heatmaps y drilldowns de incidentes.
- **Streams:** ingresa al reproductor WebRTC (URL incluida en la salida) para ver transmisiones en vivo y replay.
- **Alertas:** gatilla los escenarios de `FEATURES.md` para generar notificaciones en PagerDuty y Slack.

## 5. Envíanos Feedback
¿Necesitas demos extendidas, sesiones conjuntas o integraciones a medida? Escríbenos a `solutions@multicloud-surveillance.demo` con tu caso de uso.
