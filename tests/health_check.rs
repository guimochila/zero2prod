use std::net::TcpListener;

use sqlx::{PgPool, Pool, Postgres};
use zero2prod::startup::run;

pub struct TestApp {
    pub address: String,
    pub db_pool: PgPool,
}

async fn spawn_app(pool: Pool<Postgres>) -> TestApp {
    let listener = TcpListener::bind("127.0.0.1:0").expect("Failed to bind random port.");
    let port = listener.local_addr().unwrap().port();
    let address = format!("http://127.0.0.1:{}", port);

    let server = run(listener, pool.clone()).expect("Failed to bind address.");
    let _ = tokio::spawn(server);

    TestApp {
        address,
        db_pool: pool,
    }
}

#[sqlx::test]
async fn health_check_works(pool: Pool<Postgres>) {
    let app = spawn_app(pool).await;
    let client = reqwest::Client::new();

    let response = client
        .get(&format!("{}/health_check", &app.address))
        .send()
        .await
        .expect("Failed to execute request.");

    assert!(response.status().is_success());
    assert_eq!(Some(0), response.content_length());
}

#[sqlx::test]
async fn subscribe_returns_a_200_for_valid_form_data(pool: Pool<Postgres>) {
    let app = spawn_app(pool).await;
    let client = reqwest::Client::new();

    let body = "name=engineer%20rust&email=engineer_rust%40gmail.com";
    let response = client
        .post(&format!("{}/subscriptions", &app.address))
        .header("Content-Type", "application/x-www-form-urlencoded")
        .body(body)
        .send()
        .await
        .expect("Failed to request.");

    assert_eq!(200, response.status().as_u16());

    let saved = sqlx::query!("SELECT email, name FROM subscriptions",)
        .fetch_one(&app.db_pool)
        .await
        .expect("Failed to fetch saved subscription.");

    assert_eq!(saved.email, "engineer_rust@gmail.com");
    assert_eq!(saved.name, "engineer rust");
}

#[sqlx::test]
async fn subscribe_returns_a_400_when_data_is_missing(pool: Pool<Postgres>) {
    let app = spawn_app(pool).await;
    let client = reqwest::Client::new();
    let test_cases = vec![
        ("name=engineer%20rust", "missing the email"),
        ("email=engineer_rust%40gmail.com", "missing the name"),
        ("", "missing both name and email"),
    ];

    for (invalid_body, error_message) in test_cases {
        let response = client
            .post(&format!("{}/subscriptions", &app.address))
            .header("Content-Type", "application/x-www-form-urlencoded")
            .body(invalid_body)
            .send()
            .await
            .expect("Failed to execute request");

        assert_eq!(
            400,
            response.status().as_u16(),
            "The API did not fail with 400 Bad Request when the payload was {}.",
            error_message
        );
    }
}
