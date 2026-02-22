#!/bin/bash

#PBS -q gpu@pbs-m1.metacentrum.cz
#PBS -l walltime=24:0:0
#PBS -l select=1:ncpus=2:ngpus=1:mem=16gb:gpu_mem=8gb:scratch_local=50gb:cuda_version=13.0


#This script uses conda eviroment available on metacentrum.cz
#TODO: edit this path to the location of the repository
REPO_DIR='/storage/brno2/home/abecvarov/experiments'
ENV_NAME='cuda4'

#Select parameters
DIM=256
BETA=1
ITER=0
K="1600"
PART="hdm05"
SOFTASSIGNPARAM="D0K1"


# to run the clustering, you also need to install java
# JDK_PATH="/storage/brno12-cerit/home/user/jdk-21.0.7/bin/java"
JDK_PATH="/storage/brno12-cerit/home/drking/jdk-21.0.7/bin/java"

module add conda-modules
module add mambaforge

cd "${REPO_DIR}" || {
    echo >&2 "Repository directory ${REPO_DIR} does not exist!"
    exit 1
}

# every user on metacentrum should have access to this env
conda activate "/storage/brno12-cerit/home/drking/.conda/envs/${ENV_NAME}" || {
    echo >&2 "Conda environment does not exist!"
    exit 2
}



python ${REPO_DIR}/mocap-vae-features/train.py --multirun exp=hdm05/all \
    latent_dim=${DIM} beta=${BETA} iteration=${ITER} body_model=${PART} > /dev/null 2>&1

wait

conda deactivate

# function definitions for clustering


DISTANCE_FUNCTION='de.lmu.ifi.dbs.elki.distance.distancefunction.CosineDistanceFunction'
DISTANCE_FUNCTION_PARAMS=""
ALGORITHM='clustering.kmeans.KMedoidsFastPAM'
ALGORITHM_PARAMS='-kmeans.k 3'
ELKI_JAR_PATH="${REPO_DIR}/mocap-vae-features/Implementation-Prochazka/code/clustering/jars/elki-with-distances.jar"
# My edited convertor.
CONVERTOR_JAR_PATH="${REPO_DIR}/mocap-vae-features/Implementation-Prochazka/code/clustering/jars/convertor.jar"
CLUSTER_SUBFOLDER='cluster'
ELKI_FORMAT_CLUSTER_SUBFOLDER='clusters-elki-format'
KMEDOIDS_CLUSTER_SUBFOLDER='kmedoids-clusters'
EXTRACTED_MEDOIDS_FILE='medoids.txt'

# 2. Uncomment desired functions at the bottom of the file in the Main section

# 3. Run the script as follows:
# nohup ./cluster.sh &> <output>.txt &

##########################################


function formatResultFolderName() {
    # Remove the algorithm prefix
    ALGORITHM_NAME="${ALGORITHM##*.}"
    # Replace every ' ' with '_'
    ESCAPED_ALGORITHM_PARAMS=${ALGORITHM_PARAMS//' '/'_'}
	RESULT_FOLDER_NAME="${ROOT_FOLDER_FOR_RESULTS}/${ALGORITHM_NAME}-${ESCAPED_ALGORITHM_PARAMS}"
}

function createClusters() {

    formatResultFolderName

    COMMAND="\
${JDK_PATH} \
-Xmx16G \
-jar ${ELKI_JAR_PATH} \
KDDCLIApplication \
-verbose \
-dbc.in ${DATASET_PATH} \
-time \
-algorithm ${ALGORITHM} \
-algorithm.distancefunction ${DISTANCE_FUNCTION} \
${ALGORITHM_PARAMS} \
-resulthandler ResultWriter \
-out ${RESULT_FOLDER_NAME}/${CLUSTER_SUBFOLDER}\
"


    eval "${COMMAND}"

    # Stores the run command alongside the results.
    echo "${COMMAND}" >"${RESULT_FOLDER_NAME}/${CLUSTER_SUBFOLDER}/clustering-command.txt"
}

function convertElkiClusteringFormatToElkiFormat() {

    formatResultFolderName

    mkdir -p "${RESULT_FOLDER_NAME}"/"${ELKI_FORMAT_CLUSTER_SUBFOLDER}"

    for CLUSTER_PATH in "${RESULT_FOLDER_NAME}"/"${CLUSTER_SUBFOLDER}"/cluster_*; do
        # Parses the filename (the string after the last "/")
        CLUSTER_FILENAME=$(basename "${CLUSTER_PATH}")

        COMMAND="\
${JDK_PATH} \
-jar ${CONVERTOR_JAR_PATH} \
--convert-elki-clustering-file-to-elki-format \
--elki-clustering-file=${RESULT_FOLDER_NAME}/${CLUSTER_SUBFOLDER}/${CLUSTER_FILENAME} \
"


        echo "${RESULT_FOLDER_NAME}/${ELKI_FORMAT_CLUSTER_SUBFOLDER}/${CLUSTER_FILENAME}"

        eval "${COMMAND}" >"${RESULT_FOLDER_NAME}/${ELKI_FORMAT_CLUSTER_SUBFOLDER}/${CLUSTER_FILENAME}"
    done
}

function runKMedoidsClusteringOnEveryCluster() {

    formatResultFolderName

    for CLUSTER_PATH in "${RESULT_FOLDER_NAME}"/"${ELKI_FORMAT_CLUSTER_SUBFOLDER}"/cluster_*; do
        # Parses the filename (the string after the last "/") and removes the file extension
        CLUSTER_FILENAME=$(basename "${CLUSTER_PATH%.*}")

        NUMBER_OF_OBJECTS_IN_CLUSTER=$(wc -l "${CLUSTER_PATH}" | awk -F " " '{print $1}')

        # if CLUSTER_PATH contains only one object use this object as the medoid/pivot
        if [[ "${NUMBER_OF_OBJECTS_IN_CLUSTER}" == '1' ]]; then
            mkdir -p "${RESULT_FOLDER_NAME}/${KMEDOIDS_CLUSTER_SUBFOLDER}/${CLUSTER_FILENAME}"

            # Remove commas
            ELKI_RESULT=$(sed 's/,//g' "${CLUSTER_PATH}")

            echo -e "# Cluster: Cluster\n\
# Cluster name: Cluster\n\
# Cluster noise flag: false\n\
# Cluster size: 1\n\
# Model class: de.lmu.ifi.dbs.elki.data.model.MedoidModel\n\
# Cluster Medoid: 1\n\
ID=1 ${ELKI_RESULT}" >"${RESULT_FOLDER_NAME}/${KMEDOIDS_CLUSTER_SUBFOLDER}/${CLUSTER_FILENAME}/cluster.txt"
        else
            COMMAND="\
${JDK_PATH} \
-jar ${ELKI_JAR_PATH} \
KDDCLIApplication \
-verbose \
-dbc.in ${CLUSTER_PATH} \
-time \
-algorithm clustering.kmeans.KMedoidsFastPAM \
-algorithm.distancefunction ${DISTANCE_FUNCTION} \
${DISTANCE_FUNCTION_PARAMS} \
-kmeans.k 1 \
-resulthandler ResultWriter \
-out ${RESULT_FOLDER_NAME}/${KMEDOIDS_CLUSTER_SUBFOLDER}/${CLUSTER_FILENAME} \
"
            eval "${COMMAND}" > /dev/null 2>&1

            # Stores the run command alongside the results.
            echo "${COMMAND}" > "${RESULT_FOLDER_NAME}/${KMEDOIDS_CLUSTER_SUBFOLDER}/${CLUSTER_FILENAME}/clustering-command.txt"
        fi
    done

}

function extractClusterMedoids() {

    formatResultFolderName

    for CLUSTER_FOLDER_PATH in "${RESULT_FOLDER_NAME}"/"${KMEDOIDS_CLUSTER_SUBFOLDER}"/cluster_*; do
        COMMAND="\
${JDK_PATH} \
-jar ${CONVERTOR_JAR_PATH} \
--parse-medoids-from-elki-clustering-folder \
--elki-clustering-folder=${CLUSTER_FOLDER_PATH} \
--vector-dim=${DIM}
"

        # Executes the medoid extraction. The results are appended to a single file in MESSIF format.
        eval "${COMMAND}" >>"${RESULT_FOLDER_NAME}/${EXTRACTED_MEDOIDS_FILE}"
    done
}

# The actual clustering - combines the core functionality to produce the clustering

## Composite MW clustering using ELKI
function createCompositeMWClusteringELKI() {
      	createClusters
      	convertElkiClusteringFormatToElkiFormat
      	runKMedoidsClusteringOnEveryCluster
      	extractClusterMedoids
}

###########################################
#          Clustering pipeline            #     
###########################################

echo "Starting clustering pipeline"

cd ${REPO_DIR}/mocap-vae-features/Implementation-Prochazka/code/motionvocabulary/dist/lib || exit

CLS_OBJ="messif.objects.impl.ObjectFloatVectorCosine"
TOSEQ="--tosequence"   # set if you need to convert the input file of segments to motion words _and_ merge the segments back to sequences/actions
MEMORY="12g"
VOCTYPE='-v'


CLASSPATH=${CLASSPATH:-'MESSIF.jar:MESSIF-Utility.jar:MotionVocabulary.jar:commons-cli-1.4.jar:smf-core-1.0.jar:smf-impl-1.0.jar:MCDR.jar:m-index.jar:trove4j-3.0.3.jar'}

function convert() {
	CLUSTER_FOLDER_NAME=$(basename "${CLUSTER_FOLDER_PATH}")

    mkdir -p "${OUTPUT_ROOT_PATH}"

      COMMAND="\
  ${JDK_PATH} \
  -Xmx${MEMORY} \
  -cp ${CLASSPATH} \
  messif.motionvocabulary.MotionVocabulary \
  -d ${DATAFILE} \
  -c ${CLS_OBJ} \
  --quantize ${TOSEQ} ${VOCTYPE} ${CLUSTER_FOLDER_PATH}/medoids.txt \
  --soft-assign ${SOFTASSIGNPARAM} \
  --output ${OUTPUT_ROOT_PATH}/${PART}.${SOFTASSIGNPARAM} \
  "

      eval "${COMMAND}" > /dev/null 2>&1
}


##########################################
#      Preparing data for clustering     #
##########################################

echo "Preparing data for clustering"

DATASET_PATH="${REPO_DIR}/SCL/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_segmented.data.gz"

gunzip -kf ${DATASET_PATH}

perl ${REPO_DIR}/mocap-vae-features/Implementation-Prochazka/code/clustering/scripts/convert-from-messif.pl "${REPO_DIR}/SCL/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_segmented.data" > ${REPO_DIR}/SCL/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${ITER}/elki-predictions_segmented.data

#------------------------------------

##########################################
#          K-Medoid clustering           #
##########################################

echo "Starting K-Medoid clustering"

DATASET_PATH="${REPO_DIR}/SCL/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${ITER}/elki-predictions_segmented.data"
ROOT_FOLDER_FOR_RESULTS="${REPO_DIR}/elki-clusters/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${ITER}"
ALGORITHM_PARAMS="-kmeans.k ${K}"

createCompositeMWClusteringELKI

##########################################
#        Converting to MW vocabulary     #
##########################################

echo "Converting to MW vocabulary"

DATAFILE="${REPO_DIR}/SCL/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_segmented.data.gz"
OUTPUT_ROOT_PATH="${REPO_DIR}/elki-MWs/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${ITER}/KMedoidsFastPAM--kmeans.k_${K}"
CLUSTER_FOLDER_PATH="${REPO_DIR}/elki-clusters/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${ITER}/KMedoidsFastPAM--kmeans.k_${K}"
if [[ ! -f "$DATAFILE" ]]; then
    exit 67 
fi
[ -f "${OUTPUT_ROOT_PATH}/${PART}.${SOFTASSIGNPARAM}" ] && rm "${OUTPUT_ROOT_PATH}/${PART}.${SOFTASSIGNPARAM}"
convert

##########################################
#               Evaluation               #
##########################################

echo "Starting evaluation"

rm -f "${REPO_DIR}/elki-results/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${K}/results-${ITER}.txt"

# 4nn Classification
 
echo "Starting 4nn Classification"

COMMAND="${JDK_PATH} -jar ${REPO_DIR}/mocap-vae-features/evaluator.jar \
-fp ${REPO_DIR}/elki-MWs/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${ITER}/KMedoidsFastPAM--kmeans.k_${K}/${PART}.${SOFTASSIGNPARAM} \
-dd ${REPO_DIR}/mocap-vae-features/demo_pipeline/data/category_description.txt \
-k 4 \
"
mkdir -p "${REPO_DIR}/elki-results/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${K}/"
eval "${COMMAND}" >> "${REPO_DIR}/elki-results/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${K}/results-${ITER}.txt"

# Search

echo "Starting Search"

COMMAND="${JDK_PATH} -jar ${REPO_DIR}/mocap-vae-features/evaluator.jar \
-fp ${REPO_DIR}/elki-MWs/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${ITER}/KMedoidsFastPAM--kmeans.k_${K}/${PART}.${SOFTASSIGNPARAM} \
-dd ${REPO_DIR}/mocap-vae-features/demo_pipeline/data/category_description.txt \
"
eval "${COMMAND}" >> "${REPO_DIR}/elki-results/hdm05/all/model=${PART}_lat-dim=${DIM}_beta=${BETA}/${K}/results-${ITER}.txt"

#export results

echo "Exporting results"

cd "${REPO_DIR}"

python3 "${REPO_DIR}/mocap-vae-features/to_csv.py"

echo "We are done! Check results.csv"