# syntax=docker/dockerfile:1

ARG GO_IMAGE=golang:1.24-bookworm
ARG RUNTIME_IMAGE=gcr.io/distroless/static-debian12:nonroot

FROM ${GO_IMAGE} AS build
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY crypto ./crypto
COPY vrf-enclave ./vrf-enclave

RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH:-amd64} go build \
      -trimpath \
      -ldflags="-s -w" \
      -o /out/vrf-enclave \
      ./vrf-enclave/cmd/vrf-enclave \
  && CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH:-amd64} go build \
      -trimpath \
      -ldflags="-s -w" \
      -o /out/vrf-prove \
      ./vrf-enclave/cmd/vrf-prove

FROM ${RUNTIME_IMAGE}

COPY --from=build /out/vrf-enclave /usr/local/bin/vrf-enclave
COPY --from=build /out/vrf-prove /usr/local/bin/vrf-prove

USER nonroot:nonroot
ENTRYPOINT ["/usr/local/bin/vrf-enclave"]
