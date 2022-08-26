.PHONY: deploy-pipeline upload-app

# -- Variables
PROJECT_NAME:=artifactory-ecs
S3_BUCKET:=mys3-artifacts-012345678912-eu-west-1-cfn
AWS_REGION=$(AWS_DEFAULT_REGION)
ENVIRONMENT=prod
TAGS=\
	Application=artifactory\
	Stage=${ENVIRONMENT}\
	repository=MY_REPO_URL/

# -- Resources
# make deploy-pipeline ENVIRONMENT=dev
# make deploy-pipeline ENVIRONMENT=prod
deploy-pipeline:  ## Deploy the ci/cd pipeline
	aws cloudformation deploy --stack-name $(PROJECT_NAME)-${ENVIRONMENT}-codepipeline-cfn \
		--template-file artifactory-pipeline.yaml \
		--capabilities CAPABILITY_NAMED_IAM \
		--region $(AWS_REGION) \
		--tags ${TAGS} \
		--no-fail-on-empty-changeset \
		--parameter-overrides file://config/${ENVIRONMENT}-pipeline.json

define blue
	@tput setaf 6
	@echo $1
	@tput sgr0
endef
