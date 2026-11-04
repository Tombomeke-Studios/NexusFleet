# A stand-in for a fresh Ubuntu VM that becomes a NexusInfra node: an OpenSSH server and a user "fleet" that logs in
# with an SSH key only and may use sudo without a password. No Docker: Install-NexusNode installs it (Docker step).
# The container runs privileged (see docker-compose.yml) so the Docker daemon installed later can run inside it.
FROM ubuntu:24.04

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

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
