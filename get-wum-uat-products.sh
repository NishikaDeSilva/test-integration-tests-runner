#! /bin/bash

# Copyright (c) 2018, WSO2 Inc. (http://wso2.com) All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o xtrace; set -e;

#Defined the output file path locations in testgrid home
HEADER_ACCEPT="Accept: application/json"
CONFIG_FILE_UAT=${CONFIG_FILE_UAT}
CONFIG_FILE_LIVE=${CONFIG_FILE_LIVE}
RESPONSE_TIMESTAMP=${RESPONSE_TIMESTAMP}
RESPONSE_PRODUCT=${RESPONSE_PRODUCT}
PRODUCT_LIST=${PRODUCT_LIST}
RESPONSE_CHANNEL=${RESPONSE_CHANNEL}
CHANNEL_LIST=${CHANNEL_LIST}
JOB_LIST=${JOB_LIST}
PRODUCT_ID=${PRODUCT_ID}
PRODUCT_ID_LIST=${PRODUCT_ID_LIST}

#Generating access token for WUM Live environment to get the latest live synced timestamp
createAccessTokenLive() {
	echo "Generating Access Token for Live"
    uri="https://gateway.api.cloud.wso2.com/token"
    #echo "Calling URI (POST): " ${uri}
    curl -s -X POST -H "Content-Type:application/x-www-form-urlencoded" \
         -H "Authorization:Basic ${WUM_APPKEY_LIVE}" \
         -d "grant_type=password&username=${OS_USERNAME}&password=${OS_PASSWORD}" "${uri}" \
         --output "${CONFIG_FILE_LIVE}"
    live_access_token=$( jq -r ".access_token" $CONFIG_FILE_LIVE )
}

#Generating access token for WUM UAT environment to get the product list in UAT
createAccessTokenUAT() {
	echo "Generating Access Token for UAT"
    uri="https://gateway.api.cloud.wso2.com/token"
    #echo "Calling URI (POST): " ${uri}
    curl -s -X POST -H "Content-Type:application/x-www-form-urlencoded" \
         -H "Authorization:Basic ${WUM_APPKEY_UAT}" \
         -d "grant_type=password&username=${OS_USERNAME}&password=${OS_PASSWORD}" "${uri}" \
         --output "${CONFIG_FILE_UAT}"

    #get only the access token value from the json response
    uat_access_token=$( jq -r ".access_token" $CONFIG_FILE_UAT )
}

#Get timestamp by calling to WUM Live environment to get the latest live synced timestamp
getTimestampLive() {
	echo "GET Timestamp in Live"
    uri="https://api.updates.wso2.com/updates/3.0.0/timestamps/latest"
    #echo "Calling URI (GET): " ${uri}
    curl -s -X GET -H "${HEADER_ACCEPT}" -H "Authorization:Bearer ${live_access_token}" "${uri}" --output "${RESPONSE_TIMESTAMP}"
    #get only the timestamp value from the json response
    live_timestamp=$( jq -r ".timestamp" $RESPONSE_TIMESTAMP )

		# stdout live timestamp will be retrieved from WUMUpdateVerifier.groovy
		echo $live_timestamp
}

#Get timestamp by calling to WUM UAT environment to get the latest live synced timestamp
getTimestampUAT() {
	echo "GET Timestamp in UAT"
    uri="https://gateway.api.cloud.wso2.com/t/wso2umuat/updates/3.0.0/timestamps/latest"
    #echo "Calling URI (GET): " ${uri}
    curl -s -X GET -H "${HEADER_ACCEPT}" -H "Authorization:Bearer ${uat_access_token}" "${uri}" --output "${RESPONSE_TIMESTAMP}"
    #get only the timestamp value from the json response
    uat_timestamp=$( jq -r ".timestamp" $RESPONSE_TIMESTAMP )

		# stdout uat timestamp will be retrieved from WUMUpdateVerifier.groovy
		echo $uat_timestamp
}

#Get the product list in WUM UAT environment
getProductList() {
	echo "GET Product List in UAT"
    uri="https://gateway.api.cloud.wso2.com/t/wso2umuat/updates/3.0.0/products/${live_timestamp}"
    #echo "Calling URI (GET): " ${uri}
    curl -s -X GET -H "${HEADER_ACCEPT}" -H "Authorization:Bearer ${uat_access_token}" "${uri}" --output "${RESPONSE_PRODUCT}"

    for row in $(cat "${RESPONSE_PRODUCT}" | jq -r '.[] | @base64'); do
        _jq() {
        echo ${row} | base64 --decode | jq -r ${1}
        }
        #get the product-name and product-version values from the json response
        list=$(_jq '."product-name"','."product-version"')
        echo $list >> $PRODUCT_LIST
    done

    echo "======== WUM Updated Product List ========"
    cat $PRODUCT_LIST


	if [ -s "$PRODUCT_LIST" ]
	then
	   echo "There are WUM updated product packs in UAT."
	else
  	  echo "There is/are no updated product packs for the given timestamp in UAT. Hence Skipping the process."
  	  exit 0
	fi
}

#Get the available channel list for each product from WUM UAT environment
getChannelList() {
	echo "GET Channel list for each product"
	TEST_TYPE_INTG="INTG"

    while IFS=  read -r line; do
        list=$line
        set -- $list
        product=$1
        version=$2

        #Passing each product and version to Channel GET endpoint by reading the output file - $PRODUCT_LIST
        uri="https://gateway.api.cloud.wso2.com/t/wso2umuat/channels/3.0.0/user/$product/$version"
        curl -s -X GET -H "${HEADER_ACCEPT}" -H "Authorization:Bearer ${uat_access_token}" "${uri}" --output "${RESPONSE_CHANNEL}"
        jq -r '.channels[]' "${RESPONSE_CHANNEL}" > "${CHANNEL_LIST}"
            while IFS=  read -r line; do
               allchannel=$line
               set -- $allchannel
               channel=$1
               #Generate job list for WUM update by construction its name with product-version-channel
#               if [ ${TEST_TYPE} == "$TEST_TYPE_INTG" ]; then
#	            echo "wum-intg-test-"$product"-"$version"-"$channel >> $JOB_LIST
#	           else
	            echo "wum-sce-test-"$product"-"$version"-"$channel >> $JOB_LIST
		    echo "wum-sce-test-k8s-"$product"-"$version"-"$channel >> $JOB_LIST
#	            echo "test-"$product"-"$version"-"$channel >> $JOB_LIST
#	           fi
            done < "$CHANNEL_LIST"
    done < "$PRODUCT_LIST"

    echo "======== Jenkins Job Names ========"
    cat $JOB_LIST
}

#Get the product updated ID list for each product from WUM UAT environment
getProductIdList(){
    echo "GET Product Id List"
    uri="https://gateway.api.cloud.wso2.com/t/wso2umuat/updates/3.0.0/list/${live_timestamp}"
    curl -s -X GET -H "${HEADER_ACCEPT}" -H "Authorization:Bearer ${uat_access_token}" "${uri}" --output "${PRODUCT_ID}"
        #get the update-no values from the json response
        for row in $(cat "${PRODUCT_ID}" | jq -r '.[] | @base64'); do
            _jq() {
            echo ${row} | base64 --decode | jq -r ${1}
            }
            list=$(_jq '."update-no"')
            echo $list >> $PRODUCT_ID_LIST
        done

         echo "======== WUM Updated product numbers ========"
         cat $PRODUCT_ID_LIST

}

wum_arg=$1

if [[ -z $wum_arg ]]; then
	createAccessTokenLive
	createAccessTokenUAT
	getTimestampLive
	getProductList
	getChannelList
	getProductIdList
else
	case $wum_arg in
		--get-live-timestamp)
			createAccessTokenLive
			getTimestampLive
			;;
		--get-uat-timestamp)
			createAccessTokenUAT
			getTimestampUAT
			;;
	 	--get-job-list)
			live_timestamp=$2
			createAccessTokenUAT
			getProductList
			getChannelList
			getProductIdList
			;;
		*)
			echo "Invalid argument. Please try again."
	esac
fi
