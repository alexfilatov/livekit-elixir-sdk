use once_cell::sync::Lazy;
use tokio::runtime::{Builder, Runtime};

pub static TOKIO: Lazy<Runtime> = Lazy::new(|| {
    Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("Failed to build global tokio runtime for livekit_webrtc NIF")
});

pub fn spawn<F>(future: F) -> tokio::task::JoinHandle<F::Output>
where
    F: std::future::Future + Send + 'static,
    F::Output: Send + 'static,
{
    TOKIO.spawn(future)
}
