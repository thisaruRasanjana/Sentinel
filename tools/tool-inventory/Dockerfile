FROM ballerina/ballerina:2201.13.6
USER root
COPY . /home/ballerina/
RUN chown -R ballerina:troupe /home/ballerina/
USER ballerina
RUN bal build
CMD ["bal", "run", "target/bin/tool_inventory.jar"]
