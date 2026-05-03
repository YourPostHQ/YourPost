FROM alpine:latest

RUN apk add --no-cache ca-certificates tzdata

# Install Zig (using specific version)
ARG ZIG_VERSION=0.16.0
RUN wget -q https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz \
    && tar -xf zig-linux-x86_64-${ZIG_VERSION}.tar.xz \
    && mv zig-linux-x86_64-${ZIG_VERSION} /usr/local/zig \
    && rm zig-linux-x86_64-${ZIG_VERSION}.tar.xz \
    && ln -s /usr/local/zig/zig /usr/local/bin/zig

# Install build dependencies
RUN apk add --no-cache build-base sqlite-dev openssl-dev

WORKDIR /app

# Copy source code
COPY . .

# Build the project
RUN zig build -Doptimize=ReleaseFast

# Create non-root user
RUN addgroup -g 1000 yourpost \
    && adduser -D -u 1000 -G yourpost yourpost

# Create directories
RUN mkdir -p /var/lib/yourpost/data /var/lib/yourpost/mailboxes \
    && chown -R yourpost:yourpost /var/lib/yourpost

USER yourpost

EXPOSE 25 587 465 110 995 143 993 9000 9001

VOLUME ["/var/lib/yourpost"]

ENTRYPOINT ["/app/zig-out/bin/yourpost"]
