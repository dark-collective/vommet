(() => {

    //${SEND_IPC_CODE}

    //${WIDGETS_COMMON}

    window.parent.postMessage = (message, options) => {
        var msg = encodeArrayBuffers(message);
        var data = JSON.stringify(msg)

        sendIpc(data)

    }

    let original = window.addEventListener;

    let callbacks = new Array()

    window.addEventListener = (type, callback) => {
        if (type == "message") {
            callbacks.push(callback);

        } else {
            original(type, callback);
        }
    }


    window.onMessagePolyfill = (message) => {
        var data = JSON.parse(message)
        decodeArrayBuffers(data).then((value) => {

            // Vommet: the widget is the window's own page here, so the host
            // stands in for window.parent. Widgets that check e.source (as
            // the widget API spec asks) dropped every message without it.
            var event = {
                origin: "commet://widget",
                source: window.parent,
                data: value
            }

            if (window.onmessage != null) {
                window.onmessage(event);
            }

            callbacks.forEach((i) => { i(event) });
        });
    }


    console.log("Started widget runner script");
})();