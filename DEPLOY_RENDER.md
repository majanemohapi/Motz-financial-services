# Deploy Motz Financial Services to Render

This application is a single SWI-Prolog web service. It serves both the browser dashboard and its `/api/*` endpoints from the same origin, so the dashboard can continue to use relative API URLs.

## Before publishing

- Confirm that you are allowed to redistribute `data/train.csv` under the dataset's terms and your course rules. The Docker image requires `data/train.csv` at build time. If redistribution is not allowed, do not publish this repository/image with the CSV; arrange an authorized private dataset source and adjust the build process.
- Never include the lecturer's separate out-of-sample assessment dataset.
- Do not publish private applicant data, credentials, tokens or API keys.

## Deploy using Render Blueprint

1. Push this project to the GitHub repository `majanemohapi/Motz-financial-services`.
2. Sign in to Render and connect the GitHub account that owns the repository.
3. In Render, choose **New → Blueprint** and select `Motz-financial-services`.
4. Render reads `render.yaml`, builds the Dockerfile and creates the web service.
5. Wait for the deployment to finish. Open the service URL shown by Render.
6. Verify the homepage and `https://YOUR-SERVICE.onrender.com/api/health`.
7. Test a sample prediction and check `/api/performance`, `/api/analysis` and `/api/data_quality`.

The application reads Render's `PORT` environment variable. For local Windows use, it continues to default to port 8080.

## Hosting notes

The free service may sleep after inactivity and take time to wake on the first request. This is suitable for an academic demonstration, not a guaranteed always-on production lending service. The model is an educational prototype; it must not make real lending decisions.
