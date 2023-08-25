#!/bin/bash
# 
# Copyright 2019 Shiyghan Navti. Email shiyghan@gmail.com
#
#################################################################################
###        ETL Processing on Google Cloud Using Dataflow and BigQuery        ####
#################################################################################

# User prompt function
function ask_yes_or_no() {
    read -p "$1 ([y]yes to preview, [n]o to create, [d]del to delete): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        n|no)  echo "no" ;;
        d|del) echo "del" ;;
        *)     echo "yes" ;;
    esac
}

function ask_yes_or_no_proj() {
    read -p "$1 ([y]es to change, or any key to skip): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes) echo "yes" ;;
        *)     echo "no" ;;
    esac
}

clear
MODE=1
export TRAINING_ORG_ID=$(gcloud organizations list --format 'value(ID)' --filter="displayName:techequity.training" 2>/dev/null)
export ORG_ID=$(gcloud projects get-ancestors $GCP_PROJECT --format 'value(ID)' 2>/dev/null | tail -1 )
export GCP_PROJECT=$(gcloud config list --format 'value(core.project)' 2>/dev/null)  

echo
echo
echo -e "                        👋  Welcome to Cloud Sandbox! 💻"
echo 
echo -e "              *** PLEASE WAIT WHILE LAB UTILITIES ARE INSTALLED ***"
sudo apt-get -qq install pv > /dev/null 2>&1
echo 
export SCRIPTPATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

function join_by { local IFS="$1"; shift; echo "$*"; }

mkdir -p `pwd`/gcp-dataflow-etl > /dev/null 2>&1
export SCRIPTNAME=gcp-dataflow-etl.sh
export PROJDIR=`pwd`/gcp-dataflow-etl

if [ -f "$PROJDIR/.env" ]; then
    source $PROJDIR/.env
else
cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export GCP_REGION=us-central1
export GCP_ZONE=us-central1-b
EOF
source $PROJDIR/.env
fi

# Display menu options
while :
do
clear
cat<<EOF
======================================================================
Menu for Exploring ETL Processing with Dataflow and BigQuery
----------------------------------------------------------------------
Please enter number to select your choice:
 (1) Enable APIs
 (2) Create GCS bucket, BQ dataset and copy files
 (3) Launch data injestion pipeline
 (4) Launch data transformation pipeline
 (5) Launch data enrichment pipeline
 (G) Launch user guide
 (Q) Quit
----------------------------------------------------------------------
EOF
echo "Steps performed${STEP}"
echo
echo "What additional step do you want to perform, e.g. enter 0 to select the execution mode?"
read
clear
case "${REPLY^^}" in

"0")
start=`date +%s`
source $PROJDIR/.env
echo
echo "Do you want to run script in preview mode?"
export ANSWER=$(ask_yes_or_no "Are you sure?")
cd $HOME
if [[ ! -z "$TRAINING_ORG_ID" ]]  &&  [[ $ORG_ID == "$TRAINING_ORG_ID" ]]; then
    export STEP="${STEP},0"
    MODE=1
    if [[ "yes" == $ANSWER ]]; then
        export STEP="${STEP},0i"
        MODE=1
        echo
        echo "*** Command preview mode is active ***" | pv -qL 100
    else 
        if [[ -f $PROJDIR/.${GCP_PROJECT}.json ]]; then
            echo 
            echo "*** Authenticating using service account key $PROJDIR/.${GCP_PROJECT}.json ***" | pv -qL 100
            echo "*** To use a different GCP project, delete the service account key ***" | pv -qL 100
        else
            while [[ -z "$PROJECT_ID" ]] || [[ "$GCP_PROJECT" != "$PROJECT_ID" ]]; do
                echo 
                echo "$ gcloud auth login --brief --quiet # to authenticate as project owner or editor" | pv -qL 100
                gcloud auth login  --brief --quiet
                export ACCOUNT=$(gcloud config list account --format "value(core.account)")
                if [[ $ACCOUNT != "" ]]; then
                    echo
                    echo "Copy and paste a valid Google Cloud project ID below to confirm your choice:" | pv -qL 100
                    read GCP_PROJECT
                    gcloud config set project $GCP_PROJECT --quiet 2>/dev/null
                    sleep 3
                    export PROJECT_ID=$(gcloud projects list --filter $GCP_PROJECT --format 'value(PROJECT_ID)' 2>/dev/null)
                fi
            done
            gcloud iam service-accounts delete ${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com --quiet 2>/dev/null
            sleep 2
            gcloud --project $GCP_PROJECT iam service-accounts create ${GCP_PROJECT} 2>/dev/null
            gcloud projects add-iam-policy-binding $GCP_PROJECT --member serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com --role=roles/owner > /dev/null 2>&1
            gcloud --project $GCP_PROJECT iam service-accounts keys create $PROJDIR/.${GCP_PROJECT}.json --iam-account=${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com 2>/dev/null
            gcloud --project $GCP_PROJECT storage buckets create gs://$GCP_PROJECT > /dev/null 2>&1
        fi
        export GOOGLE_APPLICATION_CREDENTIALS=$PROJDIR/.${GCP_PROJECT}.json
        cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export GCP_REGION=$GCP_REGION
export GCP_ZONE=$GCP_ZONE
EOF
        gsutil cp $PROJDIR/.env gs://${GCP_PROJECT}/${SCRIPTNAME}.env > /dev/null 2>&1
        echo
        echo "*** Google Cloud project is $GCP_PROJECT ***" | pv -qL 100
        echo "*** Google Cloud region is $GCP_REGION ***" | pv -qL 100
        echo "*** Google Cloud zone is $GCP_ZONE ***" | pv -qL 100
        echo
        echo "*** Update environment variables by modifying values in the file: ***" | pv -qL 100
        echo "*** $PROJDIR/.env ***" | pv -qL 100
        if [[ "no" == $ANSWER ]]; then
            MODE=2
            echo
            echo "*** Create mode is active ***" | pv -qL 100
        elif [[ "del" == $ANSWER ]]; then
            export STEP="${STEP},0"
            MODE=3
            echo
            echo "*** Resource delete mode is active ***" | pv -qL 100
        fi
    fi
else 
    if [[ "no" == $ANSWER ]] || [[ "del" == $ANSWER ]] ; then
        export STEP="${STEP},0"
        if [[ -f $SCRIPTPATH/.${SCRIPTNAME}.secret ]]; then
            echo
            unset password
            unset pass_var
            echo -n "Enter access code: " | pv -qL 100
            while IFS= read -p "$pass_var" -r -s -n 1 letter
            do
                if [[ $letter == $'\0' ]]
                then
                    break
                fi
                password=$password"$letter"
                pass_var="*"
            done
            while [[ -z "${password// }" ]]; do
                unset password
                unset pass_var
                echo
                echo -n "You must enter an access code to proceed: " | pv -qL 100
                while IFS= read -p "$pass_var" -r -s -n 1 letter
                do
                    if [[ $letter == $'\0' ]]
                    then
                        break
                    fi
                    password=$password"$letter"
                    pass_var="*"
                done
            done
            export PASSCODE=$(cat $SCRIPTPATH/.${SCRIPTNAME}.secret | openssl enc -aes-256-cbc -md sha512 -a -d -pbkdf2 -iter 100000 -salt -pass pass:$password 2> /dev/null)
            if [[ $PASSCODE == 'AccessVerified' ]]; then
                MODE=2
                echo && echo
                echo "*** Access code is valid ***" | pv -qL 100
                if [[ -f $PROJDIR/.${GCP_PROJECT}.json ]]; then
                    echo 
                    echo "*** Authenticating using service account key $PROJDIR/.${GCP_PROJECT}.json ***" | pv -qL 100
                    echo "*** To use a different GCP project, delete the service account key ***" | pv -qL 100
                else
                    while [[ -z "$PROJECT_ID" ]] || [[ "$GCP_PROJECT" != "$PROJECT_ID" ]]; do
                        echo 
                        echo "$ gcloud auth login --brief --quiet # to authenticate as project owner or editor" | pv -qL 100
                        gcloud auth login  --brief --quiet
                        export ACCOUNT=$(gcloud config list account --format "value(core.account)")
                        if [[ $ACCOUNT != "" ]]; then
                            echo
                            echo "Copy and paste a valid Google Cloud project ID below to confirm your choice:" | pv -qL 100
                            read GCP_PROJECT
                            gcloud config set project $GCP_PROJECT --quiet 2>/dev/null
                            sleep 3
                            export PROJECT_ID=$(gcloud projects list --filter $GCP_PROJECT --format 'value(PROJECT_ID)' 2>/dev/null)
                        fi
                    done
                    gcloud iam service-accounts delete ${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com --quiet 2>/dev/null
                    sleep 2
                    gcloud --project $GCP_PROJECT iam service-accounts create ${GCP_PROJECT} 2>/dev/null
                    gcloud projects add-iam-policy-binding $GCP_PROJECT --member serviceAccount:$GCP_PROJECT@$GCP_PROJECT.iam.gserviceaccount.com --role=roles/owner > /dev/null 2>&1
                    gcloud --project $GCP_PROJECT iam service-accounts keys create $PROJDIR/.${GCP_PROJECT}.json --iam-account=${GCP_PROJECT}@${GCP_PROJECT}.iam.gserviceaccount.com 2>/dev/null
                    gcloud --project $GCP_PROJECT storage buckets create gs://$GCP_PROJECT > /dev/null 2>&1
                fi
                export GOOGLE_APPLICATION_CREDENTIALS=$PROJDIR/.${GCP_PROJECT}.json
                cat <<EOF > $PROJDIR/.env
export GCP_PROJECT=$GCP_PROJECT
export GCP_REGION=$GCP_REGION
export GCP_ZONE=$GCP_ZONE
EOF
                gsutil cp $PROJDIR/.env gs://${GCP_PROJECT}/${SCRIPTNAME}.env > /dev/null 2>&1
                echo
                echo "*** Google Cloud project is $GCP_PROJECT ***" | pv -qL 100
                echo "*** Google Cloud region is $GCP_REGION ***" | pv -qL 100
                echo "*** Google Cloud zone is $GCP_ZONE ***" | pv -qL 100
                echo
                echo "*** Update environment variables by modifying values in the file: ***" | pv -qL 100
                echo "*** $PROJDIR/.env ***" | pv -qL 100
                if [[ "no" == $ANSWER ]]; then
                    MODE=2
                    echo
                    echo "*** Create mode is active ***" | pv -qL 100
                elif [[ "del" == $ANSWER ]]; then
                    export STEP="${STEP},0"
                    MODE=3
                    echo
                    echo "*** Resource delete mode is active ***" | pv -qL 100
                fi
            else
                echo && echo
                echo "*** Access code is invalid ***" | pv -qL 100
                echo "*** You can use this script in our Google Cloud Sandbox without an access code ***" | pv -qL 100
                echo "*** Contact support@techequity.cloud for assistance ***" | pv -qL 100
                echo
                echo "*** Command preview mode is active ***" | pv -qL 100
            fi
        else
            echo
            echo "*** You can use this script in our Google Cloud Sandbox without an access code ***" | pv -qL 100
            echo "*** Contact support@techequity.cloud for assistance ***" | pv -qL 100
            echo
            echo "*** Command preview mode is active ***" | pv -qL 100
        fi
    else
        export STEP="${STEP},0i"
        MODE=1
        echo
        echo "*** Command preview mode is active ***" | pv -qL 100
    fi
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"1")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},1i"
    echo
    echo "$ gcloud services enable --project=\$GCP_PROJECT compute.googleapis.com dataflow.googleapis.com datapipelines.googleapis.com bigquery.googleapis.com datapipelines.googleapis.com cloudscheduler.googleapis.com # to enable APIs" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},1"
    gcloud config set project $GCP_PROJECT > /dev/null 2>&1 
    echo
    echo "$ gcloud services enable --project=$GCP_PROJECT compute.googleapis.com dataflow.googleapis.com datapipelines.googleapis.com bigquery.googleapis.com datapipelines.googleapis.com cloudscheduler.googleapis.com # to enable APIs" | pv -qL 100
    gcloud services enable --project=$GCP_PROJECT compute.googleapis.com dataflow.googleapis.com datapipelines.googleapis.com bigquery.googleapis.com datapipelines.googleapis.com cloudscheduler.googleapis.com
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},1x"
    echo
    echo "*** Nothing to delete ***" | pv -qL 100
else
    export STEP="${STEP},1i"
    echo
    echo "1. Enable APIs" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"2")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},2i"   
    echo
    echo "$ gsutil mb -c regional -l \$GCP_REGION gs://\$GCP_PROJECT # to create a new regional bucket" | pv -qL 100
    echo
    echo "$ gsutil cp gs://spls/gsp290/data_files/usa_names.csv gs://\$GCP_PROJECT/data_files/ # to copy files into bucket" | pv -qL 100
    echo
    echo "$ gsutil cp gs://spls/gsp290/data_files/head_usa_names.csv gs://\$GCP_PROJECT/data_files/ # to copy files into bucket" | pv -qL 100
    echo
    echo "$ bq mk lake # to create dataset" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},2"   
    echo
    echo "$ gsutil mb -c regional -l $GCP_REGION gs://$GCP_PROJECT # to create a new regional bucket" | pv -qL 100
    gsutil mb -c regional -l $GCP_REGION gs://$GCP_PROJECT
    echo
    echo "$ gsutil -m cp -R gs://spls/gsp290/dataflow-python-examples $PROJDIR # to copy Dataflow Python Examples" | pv -qL 100
    gsutil -m cp -R gs://spls/gsp290/dataflow-python-examples $PROJDIR
    echo
    echo "$ gsutil cp gs://spls/gsp290/data_files/usa_names.csv gs://$GCP_PROJECT/data_files/ # to copy files into bucket" | pv -qL 100
    gsutil cp gs://spls/gsp290/data_files/usa_names.csv gs://$GCP_PROJECT/data_files/
    echo
    echo "$ gsutil cp gs://spls/gsp290/data_files/head_usa_names.csv gs://$GCP_PROJECT/data_files/ # to copy files into bucket" | pv -qL 100
    gsutil cp gs://spls/gsp290/data_files/head_usa_names.csv gs://$GCP_PROJECT/data_files/ 
    echo
    echo "$ bq mk lake # to create dataset" | pv -qL 100
    bq mk lake
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},2x"   
    echo
    echo "$ gcloud storage rm --recursive gs://$GCP_PROJECT # to delete bucket" | pv -qL 100
    gcloud storage rm --recursive gs://$GCP_PROJECT
    echo
    echo "$ bq rm -r -f -d $GCP_PROJECT:lake # to delete dataset" | pv -qL 100
    bq rm -r -f -d $GCP_PROJECT:lake
else
    export STEP="${STEP},2i"
    echo
    echo "1. Create GCS bucket, BQ dataset and copy files" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"3")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},3i"
    echo
    echo "$ docker run -it -e GOOGLE_APPLICATION_CREDENTIALS=/\${GCP_PROJECT}.json -v \$PROJDIR/.\${GCP_PROJECT}.json:/\${GCP_PROJECT}.json:ro -e PROJECT=\$GCP_PROJECT -v \$PROJDIR/dataflow-python-examples:/dataflow python:3.7 sh -c \"pip install apache-beam[gcp]==2.24.0 && python /dataflow/dataflow_python_examples/data_ingestion.py --project=\$GCP_PROJECT --region= --runner=DataflowRunner --staging_location=gs://\$GCP_PROJECT/test --temp_location gs://\$GCP_PROJECT/test --input gs://\$GCP_PROJECT/data_files/head_usa_names.csv --save_main_session\" # to install apache-beam and run pipeline in Python 3.7 Docker container" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},3"   
    gcloud config set project $GCP_PROJECT > /dev/null 2>&1
    echo
    echo "$ docker run -it -e GOOGLE_APPLICATION_CREDENTIALS=/${GCP_PROJECT}.json -v $PROJDIR/.${GCP_PROJECT}.json:/${GCP_PROJECT}.json:ro -e PROJECT=$GCP_PROJECT -v $PROJDIR/dataflow-python-examples:/dataflow python:3.7 sh -c \"pip install apache-beam[gcp]==2.24.0 && python /dataflow/dataflow_python_examples/data_ingestion.py --project=$GCP_PROJECT --region= --runner=DataflowRunner --staging_location=gs://$GCP_PROJECT/test --temp_location gs://$GCP_PROJECT/test --input gs://$GCP_PROJECT/data_files/head_usa_names.csv --save_main_session\" # to install apache-beam and run pipeline in Python 3.7 Docker container" | pv -qL 100
    docker run -it -e GOOGLE_APPLICATION_CREDENTIALS=/${GCP_PROJECT}.json -v $PROJDIR/.${GCP_PROJECT}.json:/${GCP_PROJECT}.json:ro -e PROJECT=$GCP_PROJECT -v $PROJDIR/dataflow-python-examples:/dataflow python:3.7 sh -c "pip install apache-beam[gcp]==2.24.0 && python /dataflow/dataflow_python_examples/data_ingestion.py --project=$GCP_PROJECT --region= --runner=DataflowRunner --staging_location=gs://$GCP_PROJECT/test --temp_location gs://$GCP_PROJECT/test --input gs://$GCP_PROJECT/data_files/head_usa_names.csv --save_main_session"
    echo 
    echo "*** Dataflow >  Job Status ***" | pv -qL 100
    echo "*** BigQuery >  lake dataset ***" | pv -qL 100
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},3x"   
    echo
    echo "*** Cancel job on console ***" | pv -qL 100
else
    export STEP="${STEP},3i"   
    echo
    echo "1. Ingest the files from Cloud Storage" | pv -qL 100
    echo "2. Filter out the header row in the files" | pv -qL 100
    echo "3. Convert the lines read to dictionary objects" | pv -qL 100
    echo "4. Output the rows to BigQuery" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"4")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},4i"
    echo
    echo "$ docker run -it -e GOOGLE_APPLICATION_CREDENTIALS=/\${GCP_PROJECT}.json -v \$PROJDIR/.\${GCP_PROJECT}.json:/\${GCP_PROJECT}.json:ro -e PROJECT=\$GCP_PROJECT -v \$PROJDIR/dataflow-python-examples:/dataflow python:3.7 sh -c \"pip install apache-beam[gcp]==2.24.0 && python /dataflow/dataflow_python_examples/data_enrichment.py --project=\$GCP_PROJECT --region= --runner=DataflowRunner --staging_location=gs://\$GCP_PROJECT/test --temp_location gs://\$GCP_PROJECT/test --input gs://\$GCP_PROJECT/data_files/head_usa_names.csv --save_main_session\" # to spin up the workers" | pv -qL 100    
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},4"   
    gcloud config set project $GCP_PROJECT > /dev/null 2>&1
    echo
    echo "$ docker run -it -e GOOGLE_APPLICATION_CREDENTIALS=/${GCP_PROJECT}.json -v $PROJDIR/.${GCP_PROJECT}.json:/${GCP_PROJECT}.json:ro -e PROJECT=$GCP_PROJECT -v $PROJDIR/dataflow-python-examples:/dataflow python:3.7 sh -c \"pip install apache-beam[gcp]==2.24.0 && python /dataflow/dataflow_python_examples/data_enrichment.py --project=$GCP_PROJECT --region= --runner=DataflowRunner --staging_location=gs://$GCP_PROJECT/test --temp_location gs://$GCP_PROJECT/test --input gs://$GCP_PROJECT/data_files/head_usa_names.csv --save_main_session\" # to spin up the workers" | pv -qL 100    
    docker run -it -e GOOGLE_APPLICATION_CREDENTIALS=/${GCP_PROJECT}.json -v $PROJDIR/.${GCP_PROJECT}.json:/${GCP_PROJECT}.json:ro -e PROJECT=$GCP_PROJECT -v $PROJDIR/dataflow-python-examples:/dataflow python:3.7 sh -c "pip install apache-beam[gcp]==2.24.0 && python /dataflow/dataflow_python_examples/data_enrichment.py --project=$GCP_PROJECT --region= --runner=DataflowRunner --staging_location=gs://$GCP_PROJECT/test --temp_location gs://$GCP_PROJECT/test --input gs://$GCP_PROJECT/data_files/head_usa_names.csv --save_main_session"
    echo 
    echo "*** Dataflow >  Job Status ***" | pv -qL 100
    echo "*** BigQuery >  lake dataset ***" | pv -qL 100
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},4x"   
    echo
    echo "*** Cancel job on console ***" | pv -qL 100
else
    export STEP="${STEP},4i"   
    echo
    echo "1. Ingest the files from Cloud Storage" | pv -qL 100
    echo "2. Filter out the header row in the files" | pv -qL 100
    echo "3. Convert the lines read to dictionary objects" | pv -qL 100
    echo "4. Output the rows to BigQuery" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"5")
start=`date +%s`
source $PROJDIR/.env
if [ $MODE -eq 1 ]; then
    export STEP="${STEP},5i"
    echo
    echo "$ docker run -it -e GOOGLE_APPLICATION_CREDENTIALS=/\${GCP_PROJECT}.json -v \$PROJDIR/.\${GCP_PROJECT}.json:/\${GCP_PROJECT}.json:ro -e PROJECT=\$GCP_PROJECT -v \$PROJDIR/dataflow-python-examples:/dataflow python:3.7 sh -c \"pip install apache-beam[gcp]==2.24.0 && python /dataflow/dataflow_python_examples/data_lake_to_mart.py --worker_disk_type=\"compute.googleapis.com/projects//zones//diskTypes/pd-ssd\" --max_num_workers=4 --project=\$GCP_PROJECT --runner=DataflowRunner --staging_location=gs://\$GCP_PROJECT/test --temp_location gs://\$GCP_PROJECT/test --save_main_session --region=\" # to spin up the workers" | pv -qL 100
elif [ $MODE -eq 2 ]; then
    export STEP="${STEP},5"   
    gcloud config set project $GCP_PROJECT > /dev/null 2>&1
    echo
    echo "$ docker run -it -e GOOGLE_APPLICATION_CREDENTIALS=/${GCP_PROJECT}.json -v $PROJDIR/.${GCP_PROJECT}.json:/${GCP_PROJECT}.json:ro -e PROJECT=$GCP_PROJECT -v $PROJDIR/dataflow-python-examples:/dataflow python:3.7 sh -c \"pip install apache-beam[gcp]==2.24.0 && python /dataflow/dataflow_python_examples/data_lake_to_mart.py --worker_disk_type=\"compute.googleapis.com/projects//zones//diskTypes/pd-ssd\" --max_num_workers=4 --project=$GCP_PROJECT --runner=DataflowRunner --staging_location=gs://$GCP_PROJECT/test --temp_location gs://$GCP_PROJECT/test --save_main_session --region=\" # to spin up the workers" | pv -qL 100
    docker run -it -e GOOGLE_APPLICATION_CREDENTIALS=/${GCP_PROJECT}.json -v $PROJDIR/.${GCP_PROJECT}.json:/${GCP_PROJECT}.json:ro -e PROJECT=$GCP_PROJECT -v $PROJDIR/dataflow-python-examples:/dataflow python:3.7 sh -c "pip install apache-beam[gcp]==2.24.0 && python /dataflow/dataflow_python_examples/data_lake_to_mart.py --worker_disk_type="compute.googleapis.com/projects//zones//diskTypes/pd-ssd" --max_num_workers=4 --project=$GCP_PROJECT --runner=DataflowRunner --staging_location=gs://$GCP_PROJECT/test --temp_location gs://$GCP_PROJECT/test --save_main_session --region="
    echo 
    echo "*** Dataflow >  Job Status ***" | pv -qL 100
    echo "*** BigQuery >  lake dataset ***" | pv -qL 100
elif [ $MODE -eq 3 ]; then
    export STEP="${STEP},5x"   
    echo
    echo "*** Cancel job on console ***" | pv -qL 100
else
    export STEP="${STEP},5i"   
    echo
    echo "1. Ingest files from 2 BigQuery sources" | pv -qL 100
    echo "2. Join the 2 data sources" | pv -qL 100
    echo "3. Filter out the header row in the files" | pv -qL 100
    echo "4. Convert the lines read to dictionary objects" | pv -qL 100
    echo "5. Output the rows to BigQuery" | pv -qL 100
fi
end=`date +%s`
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"R")
echo
echo "
  __                      __                              __                               
 /|            /         /              / /              /                 | /             
( |  ___  ___ (___      (___  ___        (___           (___  ___  ___  ___|(___  ___      
  | |___)|    |   )     |    |   )|   )| |    \   )         )|   )|   )|   )|   )|   )(_/_ 
  | |__  |__  |  /      |__  |__/||__/ | |__   \_/       __/ |__/||  / |__/ |__/ |__/  / / 
                                 |              /                                          
"
echo "
We are a group of information technology professionals committed to driving cloud 
adoption. We create cloud skills development assets during our client consulting 
engagements, and use these assets to build cloud skills independently or in partnership 
with training organizations.
 
You can access more resources from our iOS and Android mobile applications.

iOS App: https://apps.apple.com/us/app/tech-equity/id1627029775
Android App: https://play.google.com/store/apps/details?id=com.techequity.app

Email:support@techequity.cloud 
Web: https://techequity.cloud

Ⓒ Tech Equity 2022" | pv -qL 100
echo
echo Execution time was `expr $end - $start` seconds.
echo
read -n 1 -s -r -p "$ "
;;

"G")
cloudshell launch-tutorial $SCRIPTPATH/.tutorial.md
;;

"Q")
echo
exit
;;
"q")
echo
exit
;;
* )
echo
echo "Option not available"
;;
esac
sleep 1
done
