FROM ballerina/ballerina:2201.13.6
USER root
COPY . /home/ballerina/
RUN chown -R ballerina:troupe /home/ballerina/
USER ballerina
RUN if [ -f target/bin/token_issuer.jar ]; then echo "Using pre-built jar"; else bal build --skip-tests; fi
EXPOSE 9000
CMD ["bal", "run", "target/bin/token_issuer.jar"]
