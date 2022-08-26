# Artifactory Migration Steps
*artifactory_new: will be used to refer to the newly deployed environment*

*artifactory_prod: will be used to refer to the current production environment*

## Prerequisites
1. Create RDS snapshot of artifactory_prod
2. Check the CFN files and make sure the following values are set in config files and in CFN files

   1. prod-db.json, paste snapshot ARN made in step 1 This snapshot is used to create the new database
        ```yaml
        "DBSnapshotIdentifier": "arn:aws:rds:eu-west- 1:012345678912:snapshot:awsbackup:XXXXXXXXXXXXXXXXXXXXXXXXX",
        ```
   2. prod-ecs.json, we want to deploy a parallel environment with the same image as in artifactory_prod. And the port has to be 8081 and this will change when we upgrade to artifactory 7.37
        ```yaml
        "ContainerFrontendPort": "8081"
        "ImageUrl": "docker.bintray.io/jfrog/artifactory-pro:6.18.1"
        ```
   3. artifactory-ecs.yaml, comment out the R53 records these will be created after all resources have been deployed
        Artifactory_prod will remain available during the upgrade
        ```yaml
        # ArtiDNSRecord:
        #     Type: "AWS::Route53::RecordSet"
        #     Properties:
        #     AliasTarget:
        #         HostedZoneId: !Sub "{{resolve:ssm:/${Application}/${Stage}/alb/hosted-zone-id/cf}}"
        #         DNSName: !Sub "{{resolve:ssm:/${Application}/${Stage}/alb/dns/cf}}"
        #     Comment: 'Artifactory FIRSTDOMAIN'
        #     HostedZoneId: !Ref ArtiDNSHostedZoneId
        #     Name: !Join [ '', [ !FindInMap ["DnsMapping", !Ref Stage, "value"], !Ref ArtiURL ] ]
        #     Type: 'A'

        # ArtiDNSRecordSECONDDOMAIN:
        #     Type: "AWS::Route53::RecordSet"
        #     Properties:
        #     AliasTarget:
        #         HostedZoneId: !Sub "{{resolve:ssm:/${Application}/${Stage}/alb/hosted-zone-id/cf}}"
        #         DNSName: !Sub "{{resolve:ssm:/${Application}/${Stage}/alb/dns/cf}}"
        #     Comment: 'Artifactory  SECONDDOMAIN'
        #     HostedZoneId: !Ref ArtiDNSHostedZoneIdSECONDDOMAIN
        #     Name: !Join [ '', [ !FindInMap ["DnsMapping", !Ref Stage, "value"], !Ref ArtiURLSECONDDOMAIN ] ]
        #     Type: 'A'
        ```

   4. Comment out in resource ECSTaskDefinition, this is needed when we upgrade to artifactory 7.37
        ```yaml
        # Environment:
        # - Name: 'ENABLE_MIGRATION' 
        #   Value: 'y'
        ```

### EFS Sync to S3
1. Sync filestore objects to S3 with AWS Datasync (ClickOps in console) This sync can take hours depending on how much data has to be transfered, this can run in the background. **Continue with the other steps**
   1. Create location
      1. In S3 Create a folder filestore
      2. S3 bucket that was created by the pipeline (Destination)
   2. Create a new task
      1. For source select the existing EFS that contains all the artifacts
      2. For destination select the S3 location we created in step A

# Deploy pipeline
1. Deploy the pipeline
   1. make deploy-pipeline ENVIRONMENT=prod
2. Once deployed update the ECS service through console, set desired tasks to 0 (This will allow us to update the artifactory config files)

## Deploy 6.18.1
EFS Copy artifactory_prod config to artifactory_new
1. Create a temporary EC2 instance and mount the artifactory_prod EFS and the artifactory_new EFS
   1. mkdir /mnt/prod
   2. sudo mount -t nfs4 -o
   nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvp
   ort fs-XXXXXXX.efs.eu-west-1.amazonaws.com:/ /mnt/prod
   1. mkdir /mnt/new
   2. sudo mount -t nfs4 -o
   nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvp
   ort fs-XXXXXXX.efs.eu-west-1.amazonaws.com:/ /mnt/new
2. Create ZIP of artifactory_prod config files
   1. cd /mnt/prod
   2. zip -r myarchive.zip . -x data/filestore/**\*
   3. Unzip in artifactory_new EFS
   4. cd /mnt/prod
   5. unzip myarchive.zip -d /mnt/new/
   6. Change owner of files to artifactory user (-r recursively)
   7. chown -r 1030:1030 /mnt/new/

## Edit Artifactory config files
1. cd /mnt/new
2. Set database endpoint
   1. nano etc/db.properties
        Edit line 3: YOUR-ENDPOINT.eu-west-1.rds.amazonaws.com 2. type=postgresql
   2. driver=org.postgresql.Driver
   3. url=jdbc:postgresql://YOUR-ENDPOINT.eu-west-
   4. rds.amazonaws.com:5432/artifactory
   5. username=artifactory
        password=XXXXXXXXXXXXXXXXXXXXXX
3. When you need to change the "urlBase".
Artifactory will redirect you to this url when you hit the domain apex (artifactory.DOMAIN1.cloud → dev.artifactory.DOMAIN1.cloud/artifactory)
    **Currently only for DEV environment!!!**
   1. nano etc/artifactory.config.bootstrap.xml
    <urlBase>https://dev.artifactory.DOMAIN1.cloud/artifactory</url Base>
   2. Copy the file and rename it this way Artifactory will register it as a change
      1. cp etc/artifactory.config.bootstrap.xml etc/artifactory.config.import.xml
4. Update license file
    **Currently only for DEV environment!!!**
    nano etc/artifactory.lic

## Start ECS
1. Once the Datasync is complete we can update the ECS service through console, set desired tasks to 1

# Deploy 7.37.13
## Cloudformation Config changes
1. Update the artifactory_new ECS service through console, set desired tasks to 0
2. Change parameter prod-ecs.json
    1. Change the image and the port
    ```yaml
    "ImageUrl": "docker.bintray.io/jfrog/artifactory-pro:7.37.13", "ContainerFrontendPort": "8082"
    ```
    2. artifactory-ecs.yaml Uncomment the following parameter, this parameter will trigger update in Artifactory
    ```yaml
    Environment:
    - Name: 'ENABLE_MIGRATION'
      Value: 'y'
    ```
3. Push changes

## Start upgrade
1. Temporarily update the target group health check settings.
We do this because the upgrade process takes a while until it returns a 200, if we don't do this the health check will fail and stop the container.
   1. Increase all values to max and afterwards revert to default settings
1. Update the artifactory_new ECS service through console, set desired tasks to 1

## Edit Artifactory config files

1. Update the artifactory_new ECS service through console, set desired tasks to 0
2. Update binarystore.xml UPDATE BUCKET NAME
    ```yaml
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <config version="2">
        <chain template="s3-storage-v3-direct"/>
        <provider type="s3-storage-v3" id="s3-storage-v3">
            <bucketName>BUCKET-NAME</bucketName>
            <path>filestore</path>
            <endpoint>s3.amazonaws.com</endpoint>
                <useInstanceCredentials>true</useInstanceCredentials>
                <maxConnections>300</maxConnections>
                <region>eu-west-1</region>
        </provider>
    </config>
    ```
3. Update the artifactory_new ECS service through console, set desired tasks to 1
   1. Scanning all files on S3 will take a while depending on how many artifacts are available (Batches of 15000)

# Route 53 Change current DNS records
1. Hosted zone: DNSZONE1.cloud
    Change current DNS record to old.artifactory.DOMAIN.COM
2. Hosted zone: DNSZONE2.cloud
    Change current DNS record to old.artifactory.DOMAIN.COM
3. Change artifactory-ecs.yaml

   Uncomment the R53 resources
    ```yaml
    ArtiDNSRecord:
        Type: "AWS::Route53::RecordSet"
        Properties:
        AliasTarget:
            HostedZoneId: !Sub "{{resolve:ssm:/${Application}/${Stage}/alb/hosted-zone-id/cf}}"
            DNSName: !Sub "{{resolve:ssm:/${Application}/${Stage}/alb/dns/cf}}"
        Comment: 'Artifactory FIRSTDOMAIN'
        HostedZoneId: !Ref ArtiDNSHostedZoneId
        Name: !Join [ '', [ !FindInMap ["DnsMapping", !Ref Stage, "value"], !Ref ArtiURL ] ]
        Type: 'A'

    ArtiDNSRecordSECONDDOMAIN:
        Type: "AWS::Route53::RecordSet"
        Properties:
        AliasTarget:
            HostedZoneId: !Sub "{{resolve:ssm:/${Application}/${Stage}/alb/hosted-zone-id/cf}}"
            DNSName: !Sub "{{resolve:ssm:/${Application}/${Stage}/alb/dns/cf}}"
        Comment: 'Artifactory  SECONDDOMAIN'
        HostedZoneId: !Ref ArtiDNSHostedZoneIdSECONDDOMAIN
        Name: !Join [ '', [ !FindInMap ["DnsMapping", !Ref Stage, "value"], !Ref ArtiURLSECONDDOMAIN ] ]
        Type: 'A'
    ```

4. artifactory-ecs.yaml comment the following parameter
    ```yaml
    #Environment:
    #- Name: 'ENABLE_MIGRATION'
    #  Value: 'y
    ```

5. Push changes
6. (DataSync last changes again)
7. Done