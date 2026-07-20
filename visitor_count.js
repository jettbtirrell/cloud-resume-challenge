// TODO: replace this URL once the API Gateway + Lambda + DynamoDB backend is built
// (see the "Cloud Resume Challenge" project plan).
const VISITOR_COUNT_API = "https://REPLACE_ME.execute-api.us-east-1.amazonaws.com/Prod/read_count";

function getCount() {
    return fetch(VISITOR_COUNT_API)
        .then(res => res.json())
        .then(data => {
            const markup = `<p>Visitor Count: ${data.count}</p>`;
            document.querySelector(".counter_st").insertAdjacentHTML("beforeend", markup);
        })
        .catch(err => {
            console.error("Visitor counter unavailable:", err);
        });
}

document.addEventListener("DOMContentLoaded", getCount);
