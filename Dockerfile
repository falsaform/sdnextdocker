ARG UBUNTU_VERSION=22.04
ARG CUDA_VERSION=12.1.1

FROM nvidia/cuda:${CUDA_VERSION}-cudnn8-devel-ubuntu${UBUNTU_VERSION} AS builder
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends
RUN apt-get install -y curl git python3 python3-dev build-essential pkg-config ninja-build

ENV VIRTUAL_ENV=/opt/venv
ADD --chmod=755 https://astral.sh/uv/install.sh /install.sh
RUN /install.sh && rm /install.sh
ENV PIP_CACHE=/root/.cache/pip
ENV UV_CACHE=/root/.cache/uv

RUN /root/.cargo/bin/uv venv --seed ${VIRTUAL_ENV}
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

WORKDIR /build
COPY requirements.txt /build

RUN --mount=type=cache,target=${PIP_CACHE} \
    --mount=type=cache,target=${UV_CACHE} \
    /root/.cargo/bin/uv pip install --extra-index-url https://download.pytorch.org/whl/cu121 torch==2.2.0+cu121 torchvision torchaudio triton xformers

RUN --mount=type=cache,target=${PIP_CACHE} \
    --mount=type=cache,target=${UV_CACHE} \
    /root/.cargo/bin/uv pip install https://github.com/chengzeyi/stable-fast/releases/download/v1.0.4/stable_fast-1.0.4+torch220cu121-cp310-cp310-manylinux2014_x86_64.whl

RUN --mount=type=cache,target=${PIP_CACHE} \
    --mount=type=cache,target=${UV_CACHE} \
    /root/.cargo/bin/uv pip install -r requirements.txt

RUN --mount=type=cache,target=${PIP_CACHE} \
    --mount=type=cache,target=${UV_CACHE} \
    /root/.cargo/bin/uv pip install --extra-index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/onnxruntime-cuda-12/pypi/simple/ onnx onnxruntime-gpu

RUN --mount=type=cache,target=${PIP_CACHE} \
    --mount=type=cache,target=${UV_CACHE} \
    /root/.cargo/bin/uv pip install tensorflow bitsandbytes git+https://github.com/openai/CLIP.git

RUN --mount=type=cache,target=${PIP_CACHE} \
    --mount=type=cache,target=${UV_CACHE} \
    /root/.cargo/bin/uv pip install -f https://github.com/siliconflow/oneflow_releases/releases/expanded_assets/community_cu121 oneflow onediff

FROM nvidia/cuda:${CUDA_VERSION}-cudnn8-runtime-ubuntu${UBUNTU_VERSION} AS runtime

RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends
RUN apt-get install -y curl git python3 libgl1 libglib2.0-0 \
    libglfw3-dev libgles2-mesa-dev pkg-config libcairo2 libcairo2-dev

ENV VIRTUAL_ENV=/opt/venv
COPY --from=builder ${VIRTUAL_ENV} ${VIRTUAL_ENV}
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

WORKDIR /app
COPY . /app

ARG DATA_DIR=/config
VOLUME ${DATA_DIR}
RUN mkdir -p data && mv data ${DATA_DIR}
ENV SD_DATADIR=${DATA_DIR}

ARG MODELS_DIR=${DATA_DIR}/models
RUN mkdir -p models && mv models ${MODELS_DIR}
ENV SD_MODELSDIR=${MODELS_DIR}

ENV SD_CONFIG=${DATA_DIR}/config.json

ARG PORT=7860
EXPOSE ${PORT}
ENV PORT=${PORT}

RUN python3 -c "import installer; installer.install_submodules()"

CMD ["python", "launch.py", "--version", "--insecure", "--allow-code", "--listen", "--cors-origins", "*", "--skip-requirements", "--skip-torch", "--experimental"]