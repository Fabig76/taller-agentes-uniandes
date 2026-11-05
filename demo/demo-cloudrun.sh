#!/usr/bin/env bash
# Demostración guiada: desplegar una app en Google Cloud Run, paso a paso.
# Seminario Ingeniería de Software con IA Generativa · UNIANDES · 2026
#
# Uso, en Cloud Shell (console.cloud.google.com, botón >_):
#   bash <(curl -fsSL https://fabig76.github.io/taller-agentes-uniandes/demo/demo-cloudrun.sh)
#
# No usa ninguna clave real: la «clave» del paso 5 es un texto de demostración.
# Se puede volver a ejecutar las veces que haga falta.

SERVICIO="demo-despliegue"
REGION="us-central1"
CARPETA="$HOME/demo-despliegue"

AZ=$'\e[1;36m'; AM=$'\e[1;33m'; VE=$'\e[1;32m'; RO=$'\e[1;31m'; GR=$'\e[0;37m'; NO=$'\e[0m'

titulo() { echo; echo "${AZ}════════════════════════════════════════════════════════════${NO}"; echo "${AZ}  $1${NO}"; echo "${AZ}════════════════════════════════════════════════════════════${NO}"; }
explica() { echo "${GR}  $1${NO}"; }
comando() { echo; echo "${AM}  \$ $1${NO}"; }
ok() { echo "${VE}  ✔ $1${NO}"; }
error() { echo; echo "${RO}  ✘ $1${NO}"; echo; exit 1; }
pausa() { echo; read -r -p "${AM}  ▶ Presione Enter para continuar…${NO}" _ </dev/tty; }

# ---------------------------------------------------------------- 0. Proyecto
titulo "Paso 0 · ¿En qué proyecto de Google Cloud trabajamos?"
command -v gcloud >/dev/null || error "No encuentro gcloud. Ejecute esto en Cloud Shell (botón >_ de console.cloud.google.com)."
PROYECTO="$(gcloud config get-value project 2>/dev/null)"
if [ -z "$PROYECTO" ] || [ "$PROYECTO" = "(unset)" ]; then
  LISTA="$(gcloud projects list --format='value(projectId)' 2>/dev/null)"
  N="$(printf '%s\n' "$LISTA" | grep -c .)"
  if [ "$N" -eq 1 ]; then
    PROYECTO="$LISTA"
  elif [ "$N" -eq 0 ]; then
    error "No tiene proyectos. Créelo arriba a la izquierda › New project, y vuelva a ejecutar este comando."
  else
    echo "  Sus proyectos:"; gcloud projects list --format='table(projectId,name)'
    echo; read -r -p "  Escriba el ID del proyecto (columna PROJECT_ID): " PROYECTO </dev/tty
  fi
fi
gcloud config set project "$PROYECTO" >/dev/null 2>&1 || error "No pude seleccionar el proyecto «$PROYECTO». Revise el ID."
ok "Proyecto: $PROYECTO"

FACT="$(gcloud billing projects describe "$PROYECTO" --format='value(billingEnabled)' 2>/dev/null)"
if [ "$FACT" != "True" ] && [ "$FACT" != "true" ]; then
  echo "${RO}  ✘ El proyecto no tiene facturación activa (o no pude verificarla).${NO}"
  explica "Actívela en: https://console.cloud.google.com/billing/linkedaccount?project=$PROYECTO"
  explica "Sin facturación, Cloud Run no puede desplegar. Las cuentas nuevas tienen crédito de prueba."
  read -r -p "  ¿Continuar de todos modos? (s/N): " R </dev/tty
  [ "$R" = "s" ] || [ "$R" = "S" ] || exit 1
else
  ok "Facturación activa"
fi
pausa

# ---------------------------------------------------------------- 1. Servicios
titulo "Paso 1 · Encender los cuatro servicios de Google"
explica "Cloud Run ejecuta la app · Cloud Build construye la imagen"
explica "Artifact Registry guarda la imagen · Secret Manager guarda la clave"
comando "gcloud services enable run cloudbuild artifactregistry secretmanager"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com \
  || error "No se pudieron activar los servicios. ¿El proyecto tiene facturación?"
ok "Servicios activos"
pausa

# ---------------------------------------------------------------- 2. La app
titulo "Paso 2 · La app de la demostración y su Dockerfile"
mkdir -p "$CARPETA" && cd "$CARPETA" || error "No pude crear la carpeta $CARPETA"
printf 'fastapi>=0.110\nuvicorn>=0.29\n' > requirements.txt
cat > main.py <<'EOF'
import os, time
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Demo despliegue")
ARRANQUE = time.time()


class Pregunta(BaseModel):
    pregunta: str


@app.get("/health")
def health():
    # Responde rápido y SIN llamar al modelo: solo dice «estoy viva»
    return {"status": "ok", "version": os.getenv("APP_VERSION", "dev"),
            "segundos_vivo": round(time.time() - ARRANQUE)}


@app.post("/api/chat")
def chat(p: Pregunta):
    if not p.pregunta.strip():
        raise HTTPException(422, "La pregunta está vacía")
    # Dice SI encontró la clave, nunca su valor
    return {"respuesta": "Recibí: " + p.pregunta,
            "clave_configurada": bool(os.getenv("CLAVE_DEMO"))}
EOF
cat > Dockerfile <<'EOF'
FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN useradd --create-home app
USER app
ENV PORT=8080
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
EOF
printf '.git\n.env\n.env.*\n__pycache__/\n' > .dockerignore
explica "Carpeta: $CARPETA"; ls -a
echo; echo "${AM}  ── Dockerfile (la receta) ──${NO}"; cat Dockerfile
ok "App creada: /health y /api/chat"
pausa

# ---------------------------------------------------------------- 3. Desplegar
titulo "Paso 3 · Desplegar (tarda de 3 a 6 minutos)"
explica "--source .           construye la imagen con NUESTRO Dockerfile, en la nube"
explica "--memory 512Mi       memoria de la caja (con torch y e5 serían 2Gi)"
explica "--min-instances 0    se duerme sin visitas: no gasta"
explica "--max-instances 1    nunca más de una copia: cuida la factura y los datos"
explica "--set-env-vars       le entrega una variable al contenedor"
comando "gcloud run deploy $SERVICIO --source . --region $REGION --memory 512Mi --min-instances 0 --max-instances 1 --allow-unauthenticated --set-env-vars APP_VERSION=1.0"
gcloud run deploy "$SERVICIO" --source . --region "$REGION" --memory 512Mi --min-instances 0 --max-instances 1 \
  --allow-unauthenticated --set-env-vars APP_VERSION=1.0 --quiet \
  || error "El despliegue falló. Lea el mensaje de arriba; casi siempre es la facturación o un permiso."
URL="$(gcloud run services describe "$SERVICIO" --region "$REGION" --format='value(status.url)')"
ok "Desplegada en: $URL"
pausa

# ---------------------------------------------------------------- 4. Probar
titulo "Paso 4 · Probar la app en internet"
comando "curl -s $URL/health"
curl -s "$URL/health"; echo
comando "curl -s -X POST $URL/api/chat -d '{\"pregunta\":\"hola\"}'"
curl -s -X POST "$URL/api/chat" -H "Content-Type: application/json" -d '{"pregunta":"hola"}'; echo
comando "pregunta vacía → debe responder 422"
curl -s -o /dev/null -w "  código HTTP: %{http_code}\n" -X POST "$URL/api/chat" -H "Content-Type: application/json" -d '{"pregunta":""}'
echo; echo "${VE}  ▶ Abran en el navegador:  $URL/health${NO}"
explica "Fíjense: \"clave_configurada\": false. Todavía no le dimos ninguna clave."
pausa

# ---------------------------------------------------------------- 5. Secreto
titulo "Paso 5 · La clave en Secret Manager (la caja fuerte)"
explica "El .env no viaja a la nube. La clave se guarda cifrada y Cloud Run la entrega como variable."
explica "Aquí usamos un texto de demostración, NO una clave real."
comando "gcloud secrets create clave-demo --data-file=-"
if gcloud secrets describe clave-demo >/dev/null 2>&1; then
  printf %s "valor-de-demostracion" | gcloud secrets versions add clave-demo --data-file=- >/dev/null
else
  printf %s "valor-de-demostracion" | gcloud secrets create clave-demo --data-file=- >/dev/null
fi || error "No pude crear el secreto."
NUM="$(gcloud projects describe "$PROYECTO" --format='value(projectNumber)')"
comando "gcloud secrets add-iam-policy-binding clave-demo … secretAccessor"
gcloud secrets add-iam-policy-binding clave-demo \
  --member="serviceAccount:${NUM}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" >/dev/null || error "No pude dar el permiso de leer el secreto."
comando "gcloud run services update $SERVICIO --set-secrets CLAVE_DEMO=clave-demo:latest --update-env-vars APP_VERSION=1.1"
gcloud run services update "$SERVICIO" --region "$REGION" --set-secrets CLAVE_DEMO=clave-demo:latest \
  --update-env-vars APP_VERSION=1.1 --quiet || error "No pude actualizar el servicio."
comando "curl -s -X POST $URL/api/chat …"
curl -s -X POST "$URL/api/chat" -H "Content-Type: application/json" -d '{"pregunta":"hola"}'; echo
curl -s "$URL/health"; echo
ok "Ahora \"clave_configurada\": true y la versión es 1.1 (una revisión nueva). El valor no aparece en ninguna parte."
pausa

# ---------------------------------------------------------------- 6. Registros
titulo "Paso 6 · Los registros: así se averigua por qué algo falló"
comando "gcloud run services logs read $SERVICIO --region $REGION --limit 15"
gcloud run services logs read "$SERVICIO" --region "$REGION" --limit 15 2>/dev/null || explica "(Los registros pueden tardar un minuto en aparecer.)"
pausa

# ---------------------------------------------------------------- 7. Consola
titulo "Paso 7 · Arranque en frío, revisiones y presupuesto"
explica "Métricas e instancias (baja a cero sin uso) y revisiones (se puede volver a la anterior):"
echo "  https://console.cloud.google.com/run/detail/$REGION/$SERVICIO/metrics?project=$PROYECTO"
explica "Presupuesto de 5 USD con alertas al 50, 90 y 100 %:"
echo "  https://console.cloud.google.com/billing/budgets?project=$PROYECTO"
echo
ok "Demostración completa. URL pública: $URL"
explica "Para borrar el servicio al final:  gcloud run services delete $SERVICIO --region $REGION"
echo
