FROM sourcecred/sourcecred:latest
# docker build -t cred-action .
COPY ./scripts/entrypoint.sh /entrypoint.sh
COPY ./scripts/pull_request.sh /pull_request.sh
COPY ./scripts/build_static_site.sh /build_static_site.sh
ENTRYPOINT ["/bin/bash"]
CMD ["/entrypoint.sh"]
