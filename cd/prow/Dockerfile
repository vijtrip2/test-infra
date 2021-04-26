FROM quay.io/containers/buildah

ARG SERVICE
ENV SERVICE ${SERVICE}
ENV DOCKER_REPOSITORY public.ecr.aws/m6e0o0r6/controller
ENV HELM_REGISTRY public.ecr.aws/m6e0o0r6
ENV HELM_REPO chart

RUN mkdir workspace && cd workspace

COPY test-infra /workspace/test-infra
COPY ${SERVICE}-controller /workspace/${SERVICE}-controller

WORKDIR /

RUN dnf -y install \
		which \
		git \
		unzip \
        openssl \
    && curl -sL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip \
    && unzip awscliv2.zip \
    && aws/install \
    && curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 \
    && chmod +x get_helm.sh \
    && ./get_helm.sh

WORKDIR /workspace/test-infra/cd/scripts

ENTRYPOINT ["./release-controller.sh"]