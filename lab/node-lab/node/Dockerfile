# A stand-in for a fresh Ubuntu VM that becomes a NexusInfra node: an OpenSSH server and a user "fleet" that logs in
# with an SSH key only and may use sudo without a password. No Docker: Install-NexusNode installs it (Docker step).
# The container runs privileged (see docker-compose.yml) so the Docker daemon installed later can run inside it.
FROM ubuntu:25.10@sha256:7cc5e35f6567ee8c66d2abb4aab0fd866669e6207c237c3a8f0947a5c7f17092

ARG PUBKEY

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-server sudo ca-certificates iptables \
    && mkdir -p /run/sshd

RUN useradd --create-home --shell /bin/bash fleet \
    && usermod --password '*' fleet \
    && echo 'fleet ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/fleet \
    && chmod 440 /etc/sudoers.d/fleet \
    && mkdir -p /home/fleet/.ssh \
    && echo "$PUBKEY" > /home/fleet/.ssh/authorized_keys \
    && chown -R fleet:fleet /home/fleet/.ssh \
    && chmod 700 /home/fleet/.ssh \
    && chmod 600 /home/fleet/.ssh/authorized_keys \
    && sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config

# The lab registry speaks plain HTTP (Start-NodeLab.ps1 -BuildFrom). The Docker that Install-NexusNode installs
# later reads this file, so it may pull the agent image from there. Only in the lab host image, never on a real host.
RUN mkdir -p /etc/docker \
    && echo '{ "insecure-registries": ["172.29.50.30:5000"] }' > /etc/docker/daemon.json

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
