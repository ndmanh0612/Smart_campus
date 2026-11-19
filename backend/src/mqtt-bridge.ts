import { randomUUID } from 'node:crypto';
import { networkInterfaces } from 'node:os';
import { isIPv4 } from 'node:net';
import { connect } from 'mqtt';

function cameraOnLocalNetwork(address: string) {
    if (!isIPv4(address))
        return false;
    const octets = address.split('.').map(Number);
    const [first, second] = octets;
    if (first !== 10 && !(first === 172 && second >= 16 && second <= 31) &&
        !(first === 192 && second === 168))
        return false;
    return Object.values(networkInterfaces()).flat().some(iface =>
        iface?.family === 'IPv4' && !iface.internal &&
        iface.address.split('.').every((value, index) => {
            const mask = Number(iface.netmask.split('.')[index]);
            return (Number(value) & mask) === (octets[index] & mask);
        }));
}

export function startMqttBridge(env: NodeJS.ProcessEnv, apiOrigin: string) {
    if (!env.CAMPUS_MQTT_URL)
        return () => {};
    const url = new URL(env.CAMPUS_MQTT_URL);
    const { CAMPUS_MQTT_TOPIC, CAMPUS_MQTT_USERNAME, CAMPUS_MQTT_PASSWORD, CAMPUS_MQTT_DEVICE_TOKEN } = env;
    const localBroker = url.protocol === 'mqtt:' && url.hostname === '127.0.0.1';
    if ((!localBroker && url.protocol !== 'mqtts:') || url.username || url.password ||
        !CAMPUS_MQTT_TOPIC || !/^[\w-]+(?:\/[\w-]+)*$/.test(CAMPUS_MQTT_TOPIC) ||
        !CAMPUS_MQTT_USERNAME || !CAMPUS_MQTT_PASSWORD || !CAMPUS_MQTT_DEVICE_TOKEN)
        throw Error('Configure the MQTT broker, topic, credentials, and device token');

    const topic = CAMPUS_MQTT_TOPIC;
    const client = connect(url.href, {
        username: CAMPUS_MQTT_USERNAME, password: CAMPUS_MQTT_PASSWORD,
        reconnectPeriod: 2000, connectTimeout: 5000,
    });
    async function request(path: string, body?: object) {
        const response = await fetch(apiOrigin + '/api/v1' + path, {
            method: body ? 'POST' : 'GET',
            headers: {
                Authorization: 'Bearer ' + CAMPUS_MQTT_DEVICE_TOKEN,
                'Content-Type': 'application/json',
                'Idempotency-Key': randomUUID(),
            },
            body: body ? JSON.stringify(body) : undefined,
            signal: AbortSignal.timeout(4000),
        });
        if (!response.ok)
            throw Error(path + ' HTTP ' + response.status);
        return (await response.json()).data;
    }
    let syncing = false;
    async function configuration() {
        const config = await request('/device/config');
        if (!config.acknowledged)
            await request('/device/config-ack', {
                deviceId: config.deviceId, configVersion: config.configVersion,
            });
        return config;
    }
    const sync = setInterval(() => {
        if (syncing || !client.connected)
            return;
        syncing = true;
        void configuration().catch(() => {}).finally(() => { syncing = false; });
    }, 2000);
    client.on('connect', () => {
        client.subscribe([topic + '/tap', topic + '/camera'], { qos: 1 }, error => {
            console.log(error ? 'MQTT subscription failed' : 'MQTT device bridge connected');
        });
    });
    client.on('error', () => console.warn('MQTT connection failed'));

    const seen = new Set<string>();
    let queue = Promise.resolve();
    let pending = 0;
    client.on('message', (name, payload, packet) => {
        if (packet.retain || payload.length > 160)
            return;
        if (name === topic + '/camera') {
            const address = payload.toString();
            if (cameraOnLocalNetwork(address)) {
                const origin = 'http://' + address;
                if (env.FACE_PILOT_CAMERA !== origin) {
                    env.FACE_PILOT_CAMERA = origin;
                    console.log('ESP32 camera discovered at ' + origin);
                }
            }
            return;
        }
        if (name !== topic + '/tap' || pending >= 20)
            return;
        const match = /^([0-9a-f]{32}):([0-9A-F]{8}|[0-9A-F]{14}|[0-9A-F]{20})$/.exec(payload.toString());
        if (!match || seen.has(match[1]))
            return;
        seen.add(match[1]);
        if (seen.size > 1024)
            seen.delete(seen.values().next().value!);
        pending++;
        queue = queue.then(async () => {
            const [, config] = await Promise.all([
                request('/device/raw-tap', { uid: match[2] }),
                configuration()
            ]);
            console.log('MQTT card delivered to registration wizard & active context');
            if (!config || !config.context)
                return;
            const context = {
                deviceId: config.deviceId, configVersion: config.configVersion,
                contextId: config.context.id,
            };
            const challenge = await request('/device/challenges', context);
            await request('/device-events', {
                ...context, schemaVersion: 1, eventId: randomUUID(),
                deviceRole: config.role, challengeId: challenge.challengeId,
                nonce: challenge.nonce, occurredAt: new Date().toISOString(),
                credential: { type: 'RFID_UID', uid: match[2] },
            });
        }).catch(error => console.warn('MQTT tap failed: ' + error.message))
          .finally(() => { pending--; });
    });
    return () => { clearInterval(sync); client.end(true); };
}
