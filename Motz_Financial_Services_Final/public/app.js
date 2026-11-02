
/* =====================================================
   MOTZ FINANCIAL SERVICES
   LOAN PREDICTION DASHBOARD
   SWI-PROLOG API INTEGRATION
   ===================================================== */

const charts = {};

/* ---------------- API CONNECTION ---------------- */

async function getJSON(url, options = {}) {
    const response = await fetch(url, options);
    const data = await response.json();

    if (!response.ok) {
        throw new Error(data.error || `Request failed (${response.status})`);
    }

    return data;
}

const pct = value => `${Number(value || 0).toFixed(2)}%`;

function setText(selector, value) {
    const element = document.querySelector(selector);
    if (element) element.textContent = value;
}

function escapeHTML(value) {
    return String(value ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
}

/* ---------------- SERVER STATUS ---------------- */

function setConnection(connected) {
    const connection = document.querySelector('.status');
    if (!connection) return;

    connection.classList.toggle('connected', connected);
    connection.classList.toggle('disconnected', !connected);

    connection.innerHTML = connected
        ? '<i title="SWI-Prolog online"></i> Prolog Server Connected <span>Group 3<br>DIAL3110</span>'
        : '<i title="SWI-Prolog offline"></i> Prolog Server Offline <span>Start RUN_MOTZ.bat</span>';
}

/* ---------------- CHART MANAGEMENT ---------------- */

function createChart(id, config) {
    const canvas = document.getElementById(id);

    if (!canvas || typeof Chart === 'undefined') {
        console.error(`Chart.js or chart element ${id} is unavailable.`);
        return;
    }

    if (charts[id]) charts[id].destroy();

    charts[id] = new Chart(canvas, config);
}

/* ---------------- DATA HELPERS ---------------- */

function findCategory(data, category) {
    return data.find(item =>
        String(item.label).toLowerCase() === category.toLowerCase()
    ) || { approved: 0, rejected: 0 };
}

function getMissingValues(quality) {
    return quality.values || [];
}

/* ---------------- LOAD DASHBOARD ---------------- */

async function loadDashboard() {
    const health = await getJSON('/api/health');

    if (health.status !== 'ok') {
        throw new Error('Prolog server is not ready.');
    }

    setConnection(true);

    const summary = await getJSON('/api/summary');

    setText('#total', summary.total);
    setText('#approved', summary.approved);
    setText('#rejected', summary.rejected);
    setText('#accuracy', pct(summary.accuracy));

    const [analysis, quality, performanceResponse, records] =
        await Promise.all([
            getJSON('/api/analysis'),
            getJSON('/api/data_quality'),
            getJSON('/api/performance'),
            getJSON('/api/records')
        ]);

    /* The Prolog performance endpoint returns metrics inside metrics. */
    const performance = performanceResponse.metrics || performanceResponse;

    /* ---------------- STATUS CHART ---------------- */

    createChart('statusChart', {
        type: 'bar',
        data: {
            labels: ['Approved', 'Rejected'],
            datasets: [{
                label: 'Loan Applications',
                data: [summary.approved, summary.rejected],
                backgroundColor: ['#18ad78', '#ef4d54'],
                borderRadius: 7
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: false } },
            scales: { y: { beginAtZero: true } }
        }
    });

    /* ---------------- GENDER CHART ---------------- */

    const male = findCategory(analysis.gender, 'male');
    const female = findCategory(analysis.gender, 'female');

    createChart('genderChart', {
        type: 'doughnut',
        data: {
            labels: ['Male', 'Female'],
            datasets: [{
                data: [
                    male.approved + male.rejected,
                    female.approved + female.rejected
                ],
                backgroundColor: ['#287bea', '#f45d96']
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { position: 'bottom' } }
        }
    });

    /* ---------------- EDUCATION CHART ---------------- */

    const graduate = findCategory(analysis.education, 'graduate');
    const notGraduate = findCategory(analysis.education, 'not graduate');

    createChart('educationChart', {
        type: 'doughnut',
        data: {
            labels: ['Graduate', 'Not Graduate'],
            datasets: [{
                data: [
                    graduate.approved + graduate.rejected,
                    notGraduate.approved + notGraduate.rejected
                ],
                backgroundColor: ['#287bea', '#ff9a28']
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { position: 'bottom' } }
        }
    });

    /* ---------------- PROPERTY AREA CHART ---------------- */

    const property = analysis.property || [];

    const urban = findCategory(property, 'urban');
    const semiurban = findCategory(property, 'semiurban');
    const rural = findCategory(property, 'rural');

    createChart('propertyChart', {
        type: 'bar',
        data: {
            labels: ['Urban', 'Semiurban', 'Rural'],
            datasets: [
                {
                    label: 'Approved',
                    data: [
                        urban.approved,
                        semiurban.approved,
                        rural.approved
                    ],
                    backgroundColor: '#18ad78'
                },
                {
                    label: 'Rejected',
                    data: [
                        urban.rejected,
                        semiurban.rejected,
                        rural.rejected
                    ],
                    backgroundColor: '#ef4d54'
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { position: 'bottom' } },
            scales: { y: { beginAtZero: true } }
        }
    });

    /* ---------------- MISSING DATA CHART ---------------- */

    const missing = getMissingValues(quality);

    createChart('missingChart', {
        type: 'bar',
        data: {
            labels: quality.labels || [],
            datasets: [{
                label: 'Missing Values',
                data: missing,
                backgroundColor: '#16a6a1',
                borderRadius: 5
            }]
        },
        options: {
            indexAxis: 'y',
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: false } },
            scales: { x: { beginAtZero: true } }
        }
    });

    /* ---------------- MODEL PERFORMANCE ---------------- */

    const metrics = document.querySelector('#metrics');

    if (metrics) {
        metrics.innerHTML = [
            ['Accuracy', performance.accuracy],
            ['Precision', performance.precision],
            ['Recall', performance.recall],
            ['Specificity', performance.specificity],
            ['F1 Score', performance.f1]
        ].map(([label, value]) => `
            <div class="metric">
                <span>${escapeHTML(label)}</span>
                <strong>${pct(value)}</strong>
            </div>
        `).join('');
    }

    /* ---------------- CONFUSION MATRIX ---------------- */

    const matrix = document.querySelector('#matrix');
    const confusion = performanceResponse.confusion || performance;

    if (matrix) {
        matrix.innerHTML = `
            <table>
                <thead>
                    <tr>
                        <th></th>
                        <th>Predicted Approved</th>
                        <th>Predicted Rejected</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <th>Actual Approved</th>
                        <td>${confusion.tp}</td>
                        <td>${confusion.fn}</td>
                    </tr>
                    <tr>
                        <th>Actual Rejected</th>
                        <td>${confusion.fp}</td>
                        <td>${confusion.tn}</td>
                    </tr>
                </tbody>
            </table>
        `;
    }

    /* ---------------- DATASET RECORDS ---------------- */

    const recordsBody = document.querySelector('#records');

    if (recordsBody) {
        recordsBody.innerHTML = (records.records || []).map(record => `
            <tr>
                <td>${escapeHTML(record.loan_id)}</td>
                <td>${escapeHTML(record.gender)}</td>
                <td>${escapeHTML(record.married)}</td>
                <td>${escapeHTML(record.dependents)}</td>
                <td>${escapeHTML(record.education)}</td>
                <td>${escapeHTML(record.status)}</td>
            </tr>
        `).join('');

        if (!records.records || records.records.length === 0) {
            recordsBody.innerHTML = `
                <tr><td colspan="6">No records available.</td></tr>
            `;
        }
    }

    console.log('Motz Financial Services dashboard loaded successfully.');
}

/* ---------------- LOAN PREDICTION ---------------- */

const loanForm = document.querySelector('#loanForm');

if (loanForm) {
    loanForm.addEventListener('submit', async event => {
        event.preventDefault();

        const formData = new FormData(loanForm);
        const data = Object.fromEntries(formData.entries());

        for (const field of [
            'applicantIncome',
            'coapplicantIncome',
            'loanAmount',
            'loanTerm',
            'creditHistory'
        ]) {
            data[field] = Number(data[field]);
        }

        const resultBox = document.querySelector('#result');
        if (!resultBox) return;

        resultBox.className = 'result show';
        resultBox.textContent = 'Processing loan application...';

        try {
            const result = await getJSON('/api/predict', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data)
            });

            if (result.success === false) {
                throw new Error(result.error || 'Prediction could not be completed.');
            }

            const approved = result.prediction === 'approved';

            resultBox.className = approved
                ? 'result show approved'
                : 'result show rejected';

            resultBox.innerHTML = `
                <div class="resulticon">${approved ? '✓' : '×'}</div>
                <h2>${approved ? 'Approved Pattern' : 'Rejected Pattern'}</h2>
                <p>${escapeHTML(result.notice)}</p>
                <p><strong>${escapeHTML(result.confidence)}</strong></p>
                <p><small>
                    This is a model prediction, not a final lending decision.
                    Human review is required.
                </small></p>
            `;
        } catch (error) {
            resultBox.className = 'result show rejected';
            resultBox.innerHTML = `
                <h3>Prediction Error</h3>
                <p>${escapeHTML(error.message)}</p>
            `;
            console.error('Prediction error:', error);
        }
    });
}

/* ---------------- ERROR HANDLING ---------------- */

function showDashboardError(error) {
    console.error('Dashboard could not connect to Prolog:', error);

    setConnection(false);
    setText('#total', 'Unavailable');
    setText('#approved', '—');
    setText('#rejected', '—');
    setText('#accuracy', '—');

    const records = document.querySelector('#records');

    if (records) {
        records.innerHTML = `
            <tr>
                <td colspan="6">
                    Unable to load records: ${escapeHTML(error.message)}
                </td>
            </tr>
        `;
    }
}

/* ---------------- INITIALIZE ---------------- */

document.addEventListener('DOMContentLoaded', () => {
    loadDashboard().catch(showDashboardError);
});
