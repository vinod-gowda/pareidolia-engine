# The Pareidolia Lab image engine, frozen: A1111 v1.10.1 + ControlNet with the exact package versions of the pod
# that worked on 2026-10-11. Models are NOT inside (24 GB) — start-pod.sh downloads them at start, byte-verified.
# Contains only open-source software: no pictures, no keys.
FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive PIP_NO_CACHE_DIR=1 \
    STABLE_DIFFUSION_REPO=https://github.com/w-e-w/stablediffusion.git \
    venv_dir=/venv PIP_CONSTRAINT=/root/lab/constraints.txt

WORKDIR /root/lab
COPY constraints.txt /root/lab/constraints.txt

RUN git clone -q https://github.com/AUTOMATIC1111/stable-diffusion-webui.git a1111 \
 && git -C a1111 checkout -q 82a973c04367123ae98bd9abdf80d9eda9b910e2 \
 && git clone -q https://github.com/Mikubill/sd-webui-controlnet.git a1111/extensions/sd-webui-controlnet \
 && git -C a1111/extensions/sd-webui-controlnet checkout -q 56cec5b2958edf3b1807b7e7b2b1b5186dbd2f81

RUN python -m venv /venv \
 && /venv/bin/pip install -q "setuptools==69.5.1" wheel \
 && cd a1111 \
 && /venv/bin/python launch.py --skip-torch-cuda-test --exit --xformers --skip-python-version-check \
 && /venv/bin/pip install -q -r extensions/sd-webui-controlnet/requirements.txt \
 && /venv/bin/pip install -q "mediapipe==0.10.14" \
 && /venv/bin/python -c "import torch, xformers, numpy, mediapipe as mp; assert hasattr(mp, 'solutions'); print('torch', torch.__version__, 'numpy', numpy.__version__)" \
 && rm -rf /root/.cache

COPY start-pod.sh agent.py /root/lab/
RUN chmod +x /root/lab/start-pod.sh
EXPOSE 3000 8188 8189
CMD ["bash", "/root/lab/start-pod.sh"]
