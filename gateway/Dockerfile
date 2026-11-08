FROM ballerina/ballerina:2201.13.6
USER root
COPY . /home/ballerina/
RUN chown -R ballerina:troupe /home/ballerina/
USER ballerina
RUN if [ -f target/bin/gateway.jar ]; then echo "Using pre-built gateway.jar"; else bal build --skip-tests; fi
CMD ["bal", "run", "target/bin/gateway.jar"]
