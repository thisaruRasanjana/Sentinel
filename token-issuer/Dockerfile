FROM ballerina/ballerina:2201.13.6
USER root
COPY . /home/ballerina/
RUN chown -R ballerina:troupe /home/ballerina/
USER ballerina
RUN bal build
EXPOSE 9000
CMD ["bal", "run", "target/bin/token_issuer.jar"]
