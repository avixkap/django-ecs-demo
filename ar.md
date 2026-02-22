graph TD
    A[Developer Pushes Code] --> B{Branch?}
    B -->|Pull Request| C[PR Workflow]
    B -->|develop| D[Staging Workflow]
    B -->|main| E[Production Workflow]
    
    C --> C1[Checkout Code]
    C1 --> C2[Setup Python]
    C2 --> C3[Install Dependencies]
    C3 --> C4[Run Linting<br/>flake8, black]
    C4 --> C5[Security Scan<br/>bandit, safety]
    C5 --> C6[Run Tests<br/>pytest]
    C6 --> C7[Coverage Report]
    C7 --> C8{Tests Pass?}
    C8 -->|Yes| C9[✓ PR Ready]
    C8 -->|No| C10[✗ Block PR]
    
    D --> D1[Run Tests]
    D1 --> D2{Tests Pass?}
    D2 -->|No| D3[✗ Stop]
    D2 -->|Yes| D4[Build Docker Image]
    D4 --> D5[Scan Image<br/>Trivy/Snyk]
    D5 --> D6{Vulnerabilities?}
    D6 -->|Critical| D7[✗ Stop]
    D6 -->|None/Low| D8[Tag: staging-SHA]
    D8 --> D9[Push to ECR]
    D9 --> D10[Update Task Definition]
    D10 --> D11[Deploy to ECS<br/>Staging Cluster]
    D11 --> D12[Health Check]
    D12 --> D13{Healthy?}
    D13 -->|Yes| D14[✓ Staging Deployed]
    D13 -->|No| D15[Rollback]
    D14 --> D16[Send Notification]
    
    E --> E1[Run Tests]
    E1 --> E2{Tests Pass?}
    E2 -->|No| E3[✗ Stop]
    E2 -->|Yes| E4[Build Docker Image]
    E4 --> E5[Scan Image]
    E5 --> E6{Vulnerabilities?}
    E6 -->|Critical| E7[✗ Stop & Alert]
    E6 -->|None/Low| E8[Tag: prod-SHA & latest]
    E8 --> E9[Push to ECR]
    E9 --> E10[Backup Current Task Def]
    E10 --> E11[Update Task Definition]
    E11 --> E12[Deploy to ECS<br/>Production Cluster]
    E12 --> E13[Run Smoke Tests]
    E13 --> E14{All Pass?}
    E14 -->|Yes| E15[Monitor Health]
    E14 -->|No| E16[Auto Rollback]
    E15 --> E17{Healthy 5min?}
    E17 -->|Yes| E18[✓ Prod Deployed]
    E17 -->|No| E19[Rollback]
    E18 --> E20[Update DNS/CDN]
    E20 --> E21[Send Success Alert]
    E16 --> E22[Send Failure Alert]
    E19 --> E22
    
    style C9 fill:#90EE90
    style C10 fill:#FFB6C6
    style D3 fill:#FFB6C6
    style D7 fill:#FFB6C6
    style D14 fill:#90EE90
    style E3 fill:#FFB6C6
    style E7 fill:#FFB6C6
    style E18 fill:#90EE90
    style E22 fill:#FFB6C6
