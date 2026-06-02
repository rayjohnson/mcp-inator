FROM golang:1.22-alpine AS builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/server ./...

FROM gcr.io/distroless/static:nonroot

COPY --from=builder /app/server /app/server

ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/app/server"]
