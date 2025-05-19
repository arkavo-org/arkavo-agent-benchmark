use actix_web::{web, App, HttpServer, HttpResponse, HttpRequest};
use serde::{Deserialize, Serialize};
use sqlx::postgres::PgPoolOptions;
use mongodb::Client;
use dotenv::dotenv;
use std::env;

// 1. Exposed secrets in source control
const HARDCODED_DB_PASSWORD: &str = "supersecret123";
const ADMIN_API_KEY: &str = "admin_key_12345";

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
struct User {
    id: i32,
    username: String,
    // 2. Insecure authentication - SHA-1 hashing
    password: String, // Stored in plaintext or weak hash
    is_admin: bool,
}

// 3. Broken access control example
async fn admin_dashboard(_req: HttpRequest) -> HttpResponse {
    // Anyone can access by adding ?admin=true to URL
    HttpResponse::Ok().body("Welcome to admin dashboard!")
}

// 4. SQL injection vulnerable endpoint
async fn search_users(query: web::Form<String>, pool: web::Data<sqlx::PgPool>) -> HttpResponse {
    let query = format!("SELECT * FROM users WHERE username = '{}'", query.0);
    let users = sqlx::query_as::<_, User>(&query)
        .fetch_all(&**pool)
        .await
        .unwrap();
    HttpResponse::Ok().json(users)
}

// 5. Security misconfiguration - wide open CORS
async fn public_data() -> HttpResponse {
    HttpResponse::Ok()
        .append_header(("Access-Control-Allow-Origin", "*"))
        .json(vec!["public", "data"])
}

// 6. Outdated dependencies - using old actix-web with known CVEs
pub async fn run_server() -> std::io::Result<()> {
    dotenv().ok();

    // 7. Missing encryption - plaintext DB connection
    let db_url = format!(
        "postgres://postgres:{}@benchmark_pg:5432/benchmark",
        env::var("DB_PASSWORD").unwrap_or(HARDCODED_DB_PASSWORD.to_string())
    );
    
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&db_url)
        .await
        .unwrap();

    // 8. Insecure deserialization
    let mongo_client = Client::with_uri_str("mongodb://benchmark_mongo:27017")
        .await
        .unwrap();

    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .app_data(web::Data::new(mongo_client.clone()))
            .route("/admin", web::get().to(admin_dashboard))
            .route("/search", web::post().to(search_users))
            .route("/public", web::get().to(public_data))
    })
    .bind(("0.0.0.0", 8080))?
    .run()
    .await
}
