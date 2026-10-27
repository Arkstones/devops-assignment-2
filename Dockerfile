# Small Alpine base image (~8 MB). Pinned to a version so builds are repeatable.
FROM alpine:3.20

LABEL maintainer="Robert Olwoch" \
      description="Linux diagnostic CLI (system, network, disk)"

# Alpine's busybox already gives us df, hostname, ip, nslookup, awk, etc.
# Extra packages:
#   bash    - the scripts are written in bash, Alpine only ships sh
#   iputils - a ping that also works for a non-root user
# --no-cache means the apk index is not kept in the image.
# We also create a normal user so the tool does not run as root.
RUN apk add --no-cache bash iputils \
    && adduser -D -H -s /sbin/nologin diag

WORKDIR /app

# copy only the application scripts (see .dockerignore for what is left out)
COPY app/ /app/

# make the scripts executable and add a "diagnostic" command to the PATH
RUN chmod 755 /app/*.sh \
    && ln -s /app/diagnostic.sh /usr/local/bin/diagnostic

USER diag

# "docker run diagnostic-tool <command>" passes <command> to the script.
# With no command it shows the help.
ENTRYPOINT ["/app/diagnostic.sh"]
CMD ["help"]
