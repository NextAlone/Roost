//! Sync transport: one `UnixStream` per call. Hello, then request/response.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

use roost_core::rpc::{Hello, HelloAck, Request, Response};
use serde::Serialize;
use serde::de::DeserializeOwned;
use serde_json::Value;

use crate::{CLIENT_VERSION, ClientError, Result};

pub(crate) struct Conn {
    reader: BufReader<UnixStream>,
    writer: UnixStream,
    next_id: u64,
}

impl Conn {
    pub(crate) fn connect(socket: &str, token: &str, hello_timeout: Duration) -> Result<Self> {
        let stream = UnixStream::connect(socket)?;
        stream.set_read_timeout(Some(hello_timeout))?;
        stream.set_write_timeout(Some(hello_timeout))?;
        let writer = stream.try_clone()?;
        let mut conn = Conn {
            reader: BufReader::new(stream),
            writer,
            next_id: 1,
        };

        let hello = Hello {
            auth_token: token.to_string(),
            client_version: CLIENT_VERSION.to_string(),
        };
        conn.write_line(&hello)?;
        let ack: HelloAck = conn.read_line_typed()?;
        if !ack.ok {
            let msg = ack.error.unwrap_or_else(|| "(no message)".into());
            if msg.contains("auth_token") {
                return Err(ClientError::Auth(msg));
            }
            if msg.contains("version") {
                return Err(ClientError::VersionMismatch {
                    server: ack.server_version,
                });
            }
            return Err(ClientError::Manifest(msg));
        }

        // Per-call connect, but the call itself can take longer than the
        // hello probe (jj invocations measured in tens of ms but worst case
        // jj fetch / status on a big repo creeps into seconds).
        Ok(conn)
    }

    pub(crate) fn call<P: Serialize, R: DeserializeOwned>(
        &mut self,
        method: &str,
        params: &P,
        timeout: Duration,
    ) -> Result<R> {
        // Bump the timeouts for the actual call now that hello succeeded.
        self.writer.set_read_timeout(Some(timeout))?;
        self.writer.set_write_timeout(Some(timeout))?;
        self.reader.get_ref().set_read_timeout(Some(timeout))?;
        self.reader.get_ref().set_write_timeout(Some(timeout))?;

        let id = self.next_id;
        self.next_id += 1;
        let req = Request::new(id, method, params);
        self.write_line(&req)?;
        let resp: Response = self.read_line_typed()?;

        if resp.id != id {
            return Err(ClientError::Decode(format!(
                "response id {} != request id {}",
                resp.id, id
            )));
        }
        if let Some(err) = resp.error {
            return Err(ClientError::Rpc {
                code: err.code,
                message: err.message,
            });
        }
        let value: Value = resp.result.unwrap_or(Value::Null);
        serde_json::from_value(value).map_err(|e| ClientError::Decode(e.to_string()))
    }

    fn write_line<T: Serialize>(&mut self, msg: &T) -> Result<()> {
        let mut line = serde_json::to_string(msg).map_err(|e| ClientError::Decode(e.to_string()))?;
        line.push('\n');
        self.writer.write_all(line.as_bytes())?;
        self.writer.flush()?;
        Ok(())
    }

    fn read_line_typed<T: DeserializeOwned>(&mut self) -> Result<T> {
        let mut buf = String::new();
        let n = self.reader.read_line(&mut buf)?;
        if n == 0 {
            return Err(ClientError::Io(std::io::Error::new(
                std::io::ErrorKind::UnexpectedEof,
                "server closed connection",
            )));
        }
        serde_json::from_str(buf.trim_end_matches('\n'))
            .map_err(|e| ClientError::Decode(e.to_string()))
    }
}

