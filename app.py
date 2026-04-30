#!/usr/bin/env python3

import os
from authlab import create_app
from werkzeug.serving import WSGIRequestHandler

app = create_app()

class NoServerHeaderRequestHandler(WSGIRequestHandler):
    def send_response(self, code, message=None):
        self.log_request(code)
        self.send_response_only(code, message)
        self.send_header("Date", self.date_time_string())

if __name__ == "__main__":
    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "5000"))

    dev_mode = os.getenv("DEV_MODE", "false").lower().strip() == "true"
    flask_debug = os.getenv("FLASK_DEBUG", "false").lower().strip() == "true"

    debug = dev_mode and flask_debug

    app.run(
        host=host,
        port=port,
        debug=debug,
        use_reloader=debug,
        request_handler=NoServerHeaderRequestHandler,
    )
