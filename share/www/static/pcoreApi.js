var pcoreApiResponse = {
    toString: function () {
        return this.status + ' ' + this.reason;
    },

    isInfo: function () {
        return this.status < 200;
    },

    isSuccess: function () {
        return this.status >= 200 && this.status < 300;
    },

    isRedirect: function () {
        return this.status >= 300 && this.status < 400;
    },

    isError: function () {
        return this.status >= 400;
    },

    isClientError: function () {
        return this.status >= 400 && this.status < 500;
    },

    isServerError: function () {
        return this.status >= 500;
    }
};

window.pcoreApi = {
    url: '/api/',
    listenEvents: null,

    _ws: null,
    _tid: 0,
    _tidCallbacks: {},
    _sendQueue: [],
    _url_resolved: null,

    connect: function () {
        if (!this._ws) {
            if (!this._url_resolved) {
                var a = document.createElement('a');

                a.href = this.url;

                var url = new URL(a.href);

                if (url.protocol != 'ws:' && url.protocol != 'wss:') {
                    if (url.protocol == 'https:') {
                        url.protocol = 'wss:';
                    } else {
                        url.protocol = 'ws:';
                    }
                }

                this.url = url.toString();

                this._url_resolved = 1;
            }

            this._ws = new WebSocket(this.url, 'pcore');

            this._ws.binaryType = 'blob';

            var me = this;

            this._ws.onopen = function (e) {
                me._onConnect(e);
            };

            this._ws.onclose = function (e) {
                me._onDisconnect(e);
            };

            this._ws.onmessage = function (e) {
                me._onMessage(e);
            };
        }
    },

    disconnect: function () {
        if (this._ws) {
            this._ws.close(1000, 'disconnected');
        }
    },

    rpcCall: function () {
        var method = arguments[0],
            cb,
            args;

        if (arguments.length > 1) {
            if (typeof arguments[arguments.length - 1] == 'function') {
                cb = arguments[arguments.length - 1];

                if (arguments.length > 2) {
                    args = Array.prototype.slice.call(arguments, 1, -1);
                }
            } else {
                args = Array.prototype.slice.call(arguments, 1);
            }
        }

        rpcCallArray(method, args, cb);
    },

    rpcCallArray: function (method, args, cb) {
        var msg = {
            type: 'rpc',
            method: method,
            args: args
        };

        this._sendQueue.push([msg, cb]);

        this._send();
    },

    fireRemoteEvent: function (key, data) {
        var msg = {
            type: 'event',
            event: {
                key: key,
                data: data
            }
        };

        this._sendQueue.push([msg, null]);

        this._send();
    },

    listenRemoteEvents: function (events) {
        var msg = {
            type: 'listen',
            events: events
        };

        this._sendQueue.push([msg, null]);

        this._send();
    },

    _send: function () {
        if (this._ws && this._ws.readyState == 1) {
            while (this._sendQueue.length) {
                var msg = this._sendQueue.pop();

                if (msg[1]) {
                    msg[0].tid = ++this._tid;

                    this._tidCallbacks[msg[0].tid] = msg[1];
                }

                this._ws.send(JSON.stringify(msg[0]));
            }

        } else {
            this.connect();
        }
    },

    _onConnect: function (e) {
        if (this.listenEvents) {
            var msg = {
                type: 'listen',
                events: this.listenEvents
            };

            this._ws.send(JSON.stringify(msg));
        }

        this._send();
    },

    _onDisconnect: function (e) {
        for (var tid in this._tidCallbacks) {
            cb = this._tidCallbacks[tid];

            delete this._tidCallbacks[tid];

            cb({
                status: e.code,
                reason: e.reason || 'Abnormal Closure'
            });
        }

        this._ws = null;

        if (this._sendQueue.length) {
            this.connect();
        }
    },

    _onMessage: function (e) {
        var tx = JSON.parse(e.data);

        if (tx.type == 'rpc') {
            if (!tx.method) {
                if (this._tidCallbacks[tx.tid]) {
                    cb = this._tidCallbacks[tx.tid];

                    delete this._tidCallbacks[tx.tid];

                    Object.setPrototypeOf(tx.result, pcoreApiResponse);

                    cb(tx.result);
                }
            }
        }
    }
};

var re = /cb=([^&]+)/;
var cb = re.exec(document.currentScript.src);

if (cb && window[cb[1]] !== undefined) {
    window[cb[1]](window.pcoreApi);
}
