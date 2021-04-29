# Container image for running ACK CD prow jobs.
FROM quay.io/containers/buildah
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
ENTRYPOINT ["/bin/bash", "-c", "echo Hello from ACK Prow CD container."]