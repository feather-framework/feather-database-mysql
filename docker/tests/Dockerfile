ARG SWIFT_VERSION=6.3
FROM swift:${SWIFT_VERSION}

WORKDIR /app

COPY . ./

RUN swift package resolve
RUN swift package clean

CMD ["swift", "test", "--parallel", "--enable-code-coverage"]
