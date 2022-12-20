const AWS = require('aws-sdk');
AWS.config.update( {
  region: 'ap-south-1'
});
const dynamodb = new AWS.DynamoDB.DocumentClient();
const dynamodbTableName = 'training-record';
const healthPath = '/health';
const trainingsPath = '/trainings';
const trainingPath = '/training';

exports.handler = async function(event) {
  console.log('Request event: ', event);
  let response;
  switch(true) {
    case event.httpMethod === 'GET' && event.path === healthPath:
      response = buildResponse(200);
      break;
    case event.httpMethod === 'GET' && event.path === trainingsPath:
      response = await getTrainings();
      break;
    case event.httpMethod === 'GET' && event.path === trainingPath:
      response = await getTraining(event.queryStringParameters.trainingId);
      break;
    case event.httpMethod === 'PUT' && event.path === trainingPath:
        response = await putTraining(JSON.parse(event.body));
        break;
    case event.httpMethod === 'POST' && event.path === trainingPath:
      response = await saveTraining(JSON.parse(event.body));
      break;
    case event.httpMethod === 'PATCH' && event.path === trainingPath:
      const requestBody = JSON.parse(event.body);
      response = await modifyTraining(requestBody.trainingId, requestBody.updateKey, requestBody.updateValue);
      break;
    case event.httpMethod === 'DELETE' && event.path === trainingPath:
      response = await deleteTraining(JSON.parse(event.body).trainingId);
      break;
    default:
      response = buildResponse(404, '404 Not Found');
  }
  return response;
}

async function getTrainings() {
  const params = {
    TableName: dynamodbTableName
  }
  const allTrainings = await scanDynamoRecords(params, []);
    const body = {
      trainings: allTrainings
  }
  return buildResponse(200, body);
}


async function getTraining(trainingId) {
  const params = {
    TableName: dynamodbTableName,
    Key: {
      'trainingId': trainingId
    }
  }
  return await dynamodb.get(params).promise().then((response) => {
    return buildResponse(200, response.Item);
  }, (error) => {
    console.error('Do your custom error handling here. I am just gonna log it: ', error);
  });
}


async function scanDynamoRecords(scanParams, itemArray) {
  try {
    const dynamoData = await dynamodb.scan(scanParams).promise();
    itemArray = itemArray.concat(dynamoData.Items);
    if (dynamoData.LastEvaluatedKey) {
      scanParams.ExclusiveStartkey = dynamoData.LastEvaluatedKey;
      return await scanDynamoRecords(scanParams, itemArray);
    }
    return itemArray;
  } catch(error) {
    console.error('Do your custom error handling here. I am just gonna log it: ', error);
  }
}

async function saveTraining(requestBody) {
  const params = {
      TableName: dynamodbTableName,
      Item: requestBody
  }
  return await dynamodb.put(params).promise().then(() => {
    const body = {
      Operation: 'SAVE',
      Message: 'SUCCESS',
      Item: requestBody
    }
    return buildResponse(200, body);
  }, (error) => {
    console.error('Do your custom error handling here. I am just gonna log it: ', error);
  })
}
  

async function putTraining(requestBody) {
  const params = {
    TableName: dynamodbTableName,
    Item: requestBody
  }
  return await dynamodb.put(params).promise().then(() => {
    const body = {
      Operation: 'SAVE',
      Message: 'SUCCESS',
      Item: requestBody
    }
    return buildResponse(200, body);
  }, (error) => {
    console.error('Do your custom error handling here. I am just gonna log it: ', error);
  })
}

async function modifyTraining(trainingId, updateKey, updateValue) {
  const params = {
    TableName: dynamodbTableName,
    Key: {
      'trainingId': trainingId
    },
    UpdateExpression: `set ${updateKey} = :value`,
    ExpressionAttributeValues: {
      ':value': updateValue
    },
    ReturnValues: 'UPDATED_NEW'
  }
  return await dynamodb.update(params).promise().then((response) => {
    const body = {
      Operation: 'UPDATE',
      Message: 'SUCCESS',
      UpdatedAttributes: response
    }
    return buildResponse(200, body);
  }, (error) => {
    console.error('Do your custom error handling here. I am just gonna log it: ', error);
  })
}

async function deleteTraining(trainingId) {
  const params = {
    TableName: dynamodbTableName,
    Key: {
      'trainingId': trainingId
    },
    ReturnValues: 'ALL_OLD'
  }
  return await dynamodb.delete(params).promise().then((response) => {
    const body = {
      Operation: 'DELETE',
      Message: 'SUCCESS',
      Item: response
    }
    return buildResponse(200, body);
  }, (error) => {
    console.error('Do your custom error handling here. I am just gonna log it: ', error);
  })
}

function buildResponse(statusCode, body) {
  return {
    statusCode: statusCode,
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  }
}