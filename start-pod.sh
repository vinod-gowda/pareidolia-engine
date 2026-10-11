#!/bin/bash
# Runs when the pod starts. The engine is already installed in the image; this only fetches the models
# (about 3 minutes), starts the API on :3000 and keeps the pod alive. Progress: port 8188 /bootstrap.log
W=/root/lab; A=$W/a1111; M=$A/models; HF=https://huggingface.co
cd $W
python3 -m http.server 8188 --directory $W >/dev/null 2>&1 &
[ -n "$AGENT_TOKEN" ] && python3 $W/agent.py >/dev/null 2>&1 &
exec > >(tee -a $W/bootstrap.log) 2>&1
step() { echo "=== $(date +%H:%M:%S) $*"; }

# hard stop: the pod removes itself after AUTO_STOP_MINUTES whatever else happens
( sleep $(( ${AUTO_STOP_MINUTES:-60} * 60 )); echo auto-stop; runpodctl remove pod "$RUNPOD_POD_ID" ) &

fetch() {   # url dest — refuses anything that is not byte-exact
  local want have
  want=$(curl -sIL "$1" | grep -i -E "^(x-linked-size|content-length)" | tail -1 | tr -dc 0-9)
  have=0; [ -f "$2" ] && have=$(stat -c%s "$2")
  if [ -n "$want" ] && [ "$have" = "$want" ]; then echo "OK   $2"; return 0; fi
  echo "GET  $2 ($want bytes)"; mkdir -p "$(dirname "$2")"
  for i in 1 2 3 4 5; do curl -sSL -C - --retry 5 -o "$2" "$1" && break; sleep 3; done
  have=$(stat -c%s "$2"); [ "$have" = "$want" ] || { echo "SIZE MISMATCH $2 have=$have want=$want"; return 1; }
}

step "models (parallel, byte-verified)"
(
fetch $HF/SG161222/Realistic_Vision_V5.1_noVAE/resolve/main/Realistic_Vision_V5.1_fp16-no-ema.safetensors $M/Stable-diffusion/realisticVisionV51.safetensors &&
fetch $HF/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors $M/VAE/vae-ft-mse-840000-ema-pruned.safetensors &&
fetch $HF/monster-labs/control_v1p_sd15_qrcode_monster/resolve/main/v2/control_v1p_sd15_qrcode_monster_v2.safetensors $M/ControlNet/control_v1p_sd15_qrcode_monster_v2.safetensors &&
fetch $HF/latentcat/latentcat-controlnet/resolve/main/models/control_v1p_sd15_brightness.safetensors $M/ControlNet/control_v1p_sd15_brightness.safetensors &&
fetch $HF/lllyasviel/ControlNet-v1-1/resolve/main/control_v11f1e_sd15_tile.pth $M/ControlNet/control_v11f1e_sd15_tile.pth &&
fetch $HF/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth $M/ESRGAN/4x-UltraSharp.pth
) & P1=$!
P2=""
if [ "${WITH_SDXL:-1}" = "1" ]; then (
fetch $HF/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors $M/Stable-diffusion/sd_xl_base_1.0.safetensors &
fetch $HF/RunDiffusion/Juggernaut-XL-v9/resolve/main/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors $M/Stable-diffusion/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors &
fetch $HF/monster-labs/control_v1p_sdxl_qrcode_monster/resolve/main/diffusion_pytorch_model.safetensors $M/ControlNet/control_v1p_sdxl_qrcode_monster.safetensors &
fetch $HF/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors $M/VAE/sdxl_vae_fp16_fix.safetensors &
wait
) & P2=$!; fi
wait $P1 || { echo "BOOTSTRAP-FINISHED exit=1 (a model failed to download)"; sleep infinity; }
[ -n "$P2" ] && wait $P2
step "models ready: $(du -sh $M | cut -f1)"

cat > $W/start.sh <<'START'
#!/bin/bash
# (Re)start the API. Safe to run again after a repair.
pkill -f "launch.py" 2>/dev/null; sleep 1
cd /root/lab/a1111
nohup /venv/bin/python launch.py --api --listen --port 3000 --xformers --no-half-vae --skip-python-version-check \
      --skip-install --disable-console-progressbars --ckpt /root/lab/a1111/models/Stable-diffusion/realisticVisionV51.safetensors > /root/lab/a1111.log 2>&1 &
echo started
START
chmod +x $W/start.sh
step "starting API on :3000"
bash $W/start.sh
# keep the engine alive: it once died silently after an hour of switching models
( while true; do sleep 20; pgrep -f 'launch.py' >/dev/null || { echo "$(date +%H:%M:%S) engine was down - restarting" >> $W/watch.log; bash $W/start.sh >/dev/null 2>&1; sleep 60; }; done ) &
echo "BOOTSTRAP-FINISHED exit=0"
sleep infinity
