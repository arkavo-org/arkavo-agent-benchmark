extern crate benchmark_server;
extern crate actix_web;
extern crate criterion;

use benchmark_server::run_server;
use actix_web::test::TestRequest;
use criterion::{black_box, criterion_group, Criterion};
use std::thread;

fn normal_benchmark(c: &mut Criterion) {
    // Start server in background thread
    thread::spawn(|| {
        actix_web::rt::System::new().block_on(run_server()).unwrap();
    });

    let mut group = c.benchmark_group("Normal Operations");
    
    // Test valid admin access
    group.bench_function("admin_dashboard", |b| {
        b.iter(|| {
            let req = TestRequest::get()
                .uri("/admin?admin=true")
                .to_request();
            black_box(req);
        });
    });

    // Test secure search
    group.bench_function("secure_search", |b| {
        b.iter(|| {
            let req = TestRequest::post()
                .uri("/search")
                .set_json(&"safe_query")
                .to_request();
            black_box(req);
        });
    });

    // Test public data access
    group.bench_function("public_data", |b| {
        b.iter(|| {
            let req = TestRequest::get()
                .uri("/public")
                .to_request();
            black_box(req);
        });
    });

    group.finish();
}

use actix_web::test;

#[derive(serde::Serialize)]
struct TestResult {
    name: String,
    passed: bool,
    weight: u32,
}

use reqwest;

async fn run_tests() -> Vec<TestResult> {
    let mut results = Vec::new();
    let client = reqwest::Client::new();

    // Test admin dashboard
    let admin_resp = client.get("http://benchmark_server:8080/admin?admin=true")
        .send()
        .await;
    results.push(TestResult {
        name: "admin_dashboard".to_string(),
        passed: admin_resp.is_ok(),
        weight: 3,
    });

    // Test secure search
    let search_resp = client.post("http://benchmark_server:8080/search")
        .json(&"safe_query")
        .send()
        .await;
    results.push(TestResult {
        name: "secure_search".to_string(),
        passed: search_resp.is_ok(),
        weight: 2,
    });

    // Test public data
    let public_resp = client.get("http://benchmark_server:8080/public")
        .send()
        .await;
    results.push(TestResult {
        name: "public_data".to_string(),
        passed: public_resp.is_ok(),
        weight: 1,
    });

    results
}

#[actix_web::main]
async fn main() {
    // Run tests once and output JSON results
    let results = run_tests().await;
    println!("{}", serde_json::to_string_pretty(&results).unwrap());
}

criterion_group!(benches, normal_benchmark);
