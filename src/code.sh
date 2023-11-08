#!/bin/bash

function main() {
    set -e -x -o pipefail   # Output each line as executed, exit bash on error

    dx-download-all-inputs --parallel

    OUTDIR=/home/dnanexus/out

    echo "Making logfile outdir"
    LOGFILE_OUTDIR=${OUTDIR}/logfile/qiagen_upload
    mkdir -p $LOGFILE_OUTDIR

    echo "Getting qiagen_upload docker image"
    DOCKER_FILEID='project-ByfFPz00jy1fk6PjpZ95F27J:file-Gb54J300jy1pVBFVG6KYZxPb'
    dx download $DOCKER_FILEID
    DOCKER_FILENAME=$(dx describe $DOCKER_FILEID --name)
    # --force-local required as if tarfile name contains a colon it tries to resolve the tarfile to a machine name
    DOCKER_IMAGENAME=$(tar xfO $DOCKER_FILENAME manifest.json --force-local | sed -E 's/.*"RepoTags":\["?([^"]*)"?.*/\1/')
    docker load < "$DOCKER_FILENAME"  # Load docker image
    sudo docker images
    AUTH_PROJ='project-FQqXfYQ0Z0gqx7XG9Z2b4K43'
    echo "Getting secrets"
    CLIENT_ID=$(dx cat $AUTH_PROJ:qiagen_client_id)
    CLIENT_SECRET=$(dx cat $AUTH_PROJ:qiagen_client_secret)
    AUTH_TOKEN=$(dx cat project-FQqXfYQ0Z0gqx7XG9Z2b4K43:mokaguys_nexus_auth_key)

    mkdir -p $LOGFILE_OUTDIR $CODE_VERIFIER_OUTDIR $DEVICE_CODE_OUTDIR $USER_CODE_OUTDIR $SAMPLE_ZIP_OUTDIR # Create out dir


    if [[ -z $sample_zip_folder || -z $sample_name ]];  # Determine app running mode
        then
            echo "Script is being run in get_user_code mode"

            echo "Creating output dirs"
            CODE_VERIFIER_OUTDIR=${OUTDIR}/code_verifier_file/qiagen_upload
            DEVICE_CODE_OUTDIR=${OUTDIR}/device_code_file/qiagen_upload
            USER_CODE_OUTDIR=${OUTDIR}/user_code_file/qiagen_upload
            mkdir -p $CODE_VERIFIER_OUTDIR $DEVICE_CODE_OUTDIR $USER_CODE_OUTDIR

            echo "Generating docker cmd"
            DOCKER_CMD="docker run --rm -v $OUTDIR:/qiagen_upload/outputs/ $DOCKER_IMAGENAME get_user_code -CI $CLIENT_ID"
            
            echo "Running docker cmd"
            eval $DOCKER_CMD

            # to do dx upload need to reset worker variable
            unset DX_WORKSPACE_ID
            CURRENT_PROJECT=$DX_PROJECT_CONTEXT_ID
            # set the project the worker will upload to
            dx cd $AUTH_PROJ

            echo "Checking if code_verifier file exists in 001_Auth project"
            if [[ $(dx cat $AUTH_PROJ:qiagen_code_verifier*) ]];
                then
                    echo "Removing existing code_verifier file from 001_Auth"
                    dx rm -f $AUTH_PROJ:qiagen_code_verifier* --auth-token ${AUTH_TOKEN}
                else
                    echo "code_verifier file is not present in 001_Auth project"
            fi
            echo "Checking if device_code file exists in 001_Auth project"
            if [[ $(dx cat $AUTH_PROJ:qiagen_device_code*) ]];
                then
                    echo "Removing existing device_code file from 001_Auth"
                    dx rm -f $AUTH_PROJ:qiagen_device_code* --auth-token ${AUTH_TOKEN}
                else
                    echo "device_code file is not present in 001_Auth project"
            fi

            echo "Uploading new code verifier and device code files to 001_Auth project"
            dx upload ${OUTDIR}/qiagen_code_verifier*
            dx upload ${OUTDIR}/qiagen_device_code*

            # set the project the worker will upload to
            dx cd $CURRENT_PROJECT

            echo "Moving outputs into output folders to delocalise into dnanexus project"
            mv ${OUTDIR}/*.log $LOGFILE_OUTDIR
            mv ${OUTDIR}/qiagen_device_code* $DEVICE_CODE_OUTDIR
            mv ${OUTDIR}/qiagen_user_code* $USER_CODE_OUTDIR
            mv ${OUTDIR}/qiagen_code_verifier* $CODE_VERIFIER_OUTDIR
        else
            echo "Script is being run in qiagen_upload mode"
            echo "Getting secrets"
            CODE_VERIFIER=$(dx cat $AUTH_PROJ:qiagen_code_verifier*)
            DEVICE_CODE=$(dx cat $AUTH_PROJ:qiagen_device_code*)

            echo "Creating output dir"
            XML_OUTDIR=${OUTDIR}/sample_xml/qiagen_upload
            mkdir -p $XML_OUTDIR

            echo "Generating docker cmd"
            DOCKER_CMD="docker run --rm -v $sample_zip_folder_path:/qiagen_upload/$sample_zip_folder_name -v $OUTDIR:/qiagen_upload/outputs/ $DOCKER_IMAGENAME qiagen_upload -S $sample_name -Z /qiagen_upload/$sample_zip_folder_name -CI $CLIENT_ID -CS $CLIENT_SECRET -C $CODE_VERIFIER -D $DEVICE_CODE"
            
            echo "Running docker cmd"
            eval $DOCKER_CMD

            echo "Moving outputs into output folders to delocalise into dnanexus project"
            ls $OUTDIR
            mv ${OUTDIR}/*.log $LOGFILE_OUTDIR
            unzip ${OUTDIR}/*.zip -d $OUTDIR
            mv ${OUTDIR}/*.xml $XML_OUTDIR
    fi

    dx-upload-all-outputs --parallel

}