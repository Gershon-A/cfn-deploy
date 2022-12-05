FROM  amazon/aws-cli:2.9.4

LABEL version="1.0.0"

LABEL "maintainer"="Mridhul Pax <mridhuljospax@gmail.com>"
LABEL "repository"="https://github.com/intuit/cfn-deploy"

LABEL com.github.actions.name="Cloudformation Github Deploy"
LABEL com.github.actions.description="Cloudformation Github Deploy"
LABEL com.github.actions.icon="upload-cloud"
LABEL com.github.actions.color="orange"

ENV DEBIAN_FRONTEND noninteractive

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
