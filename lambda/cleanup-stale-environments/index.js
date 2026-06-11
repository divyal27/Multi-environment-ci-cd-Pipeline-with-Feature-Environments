const {
  ECSClient,
  UpdateServiceCommand,
  DescribeServicesCommand,
  ListServicesCommand,
} = require("@aws-sdk/client-ecs");
const {
  CloudWatchClient,
  DescribeAlarmsCommand,
  SetAlarmStateCommand,
} = require("@aws-sdk/client-cloudwatch");
const {
  S3Client,
  PutObjectCommand,
  ListObjectsV2Command,
} = require("@aws-sdk/client-s3");

const ecs = new ECSClient({ region: process.env.AWS_REGION || "us-east-1" });
const cw = new CloudWatchClient({ region: process.env.AWS_REGION || "us-east-1" });
const s3 = new S3Client({ region: process.env.AWS_REGION || "us-east-1" });

const CLUSTER_PREFIX = "ephemeral-";
const INACTIVITY_THRESHOLD_HOURS = 24;
const STALE_BUCKET = process.env.STALE_BUCKET || "ephemeral-env-stale-tracker";

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function listEphemeralClusters() {
  const clusters = [];
  let token;
  do {
    const cmd = { nextToken: token };
    const resp = await ecs.send(new ListServicesCommand(cmd));
    // ECS ListServices returns ARNs; we filter by cluster prefix
    const matched = (resp.serviceArns || []).filter((arn) =>
      arn.includes(CLUSTER_PREFIX)
    );
    clusters.push(...matched);
    token = resp.nextToken;
  } while (token);
  return clusters;
}

async function getInactiveAlarms() {
  const alarms = [];
  let token;
  do {
    const resp = await cw.send(
      new DescribeAlarmsCommand({
        alarmTypes: ["MetricAlarm"],
        stateValue: "ALARM",
        alarmNamePrefix: "ephemeral-",
        nextToken: token,
      })
    );
    alarms.push(...(resp.metricAlarms || []));
    token = resp.nextToken;
  } while (token);
  return alarms;
}

async function markStale(workspace) {
  await s3.send(
    new PutObjectCommand({
      Bucket: STALE_BUCKET,
      Key: `stale/${workspace}.json`,
      Body: JSON.stringify({
        workspace,
        marked_stale_at: new Date().toISOString(),
        reason: "24h inactivity (no requests to ALB)",
      }),
    })
  );
}

async function scaleDownService(clusterName, serviceName) {
  console.log(`Scaling down ${serviceName} in ${clusterName} to 0...`);
  await ecs.send(
    new UpdateServiceCommand({
      cluster: clusterName,
      service: serviceName,
      desiredCount: 0,
    })
  );
}

async function handler() {
  console.log("Starting stale environment cleanup...");

  // Get all alarms in ALARM state (no request traffic for 24h)
  const inactiveAlarms = await getInactiveAlarms();

  if (inactiveAlarms.length === 0) {
    console.log("No inactive environments found.");
    return { statusCode: 200, body: "No stale environments." };
  }

  let destroyed = 0;
  for (const alarm of inactiveAlarms) {
    // alarm name format: ephemeral-<workspace>-inactive
    const match = alarm.AlarmName.match(/^ephemeral-(.+)-inactive$/);
    if (!match) continue;
    const workspace = match[1];

    console.log(`Environment ${workspace} is stale. Scaling down...`);

    // Mark as stale in S3 for the dashboard
    await markStale(workspace);

    // Scale ECS service to 0
    const clusterName = `ephemeral-${workspace}-cluster`;
    const serviceName = `ephemeral-${workspace}-service`;
    await scaleDownService(clusterName, serviceName);
    destroyed++;

    // Throttle to avoid API rate limits
    await sleep(500);
  }

  console.log(`Cleanup complete. Scaled down ${destroyed} stale environments.`);
  return {
    statusCode: 200,
    body: JSON.stringify({ destroyed, timestamp: new Date().toISOString() }),
  };
}

exports.handler = handler;
