
"use strict";

const healthButton = document.getElementById("healthButton");
const healthResult = document.getElementById("healthResult");
const healthCard = document.getElementById("healthCard");

const greetingForm = document.getElementById("greetingForm");
const greetingResult = document.getElementById("greetingResult");
const greetingCard = document.getElementById("greetingCard");

// Kiem tra trang thai ung dung
healthButton.addEventListener("click", async () => {
    healthButton.disabled = true;
    healthCard.dataset.state = "loading";
    healthResult.textContent = "Đang kiểm tra...";

    try {
        const response = await fetch("/health", {
            cache: "no-store"
        });

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }

        const data = await response.json();

        healthResult.textContent = JSON.stringify(data, null, 2);
        healthCard.dataset.state = "ok";
    } catch (error) {
        healthResult.textContent =
            `Kiểm tra thất bại: ${error.message}`;
        healthCard.dataset.state = "error";
    } finally {
        healthButton.disabled = false;
    }
});

// Gui yeu cau den Greeting API
greetingForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    const name = document.getElementById("name").value;
    const submitButton = greetingForm.querySelector("button");

    submitButton.disabled = true;
    greetingCard.dataset.state = "loading";
    greetingResult.textContent = "Đang gửi yêu cầu...";

    try {
        const params = new URLSearchParams({ name });

        const response = await fetch(
            `/api/greeting?${params.toString()}`
        );

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }

        const data = await response.json();

        greetingResult.textContent = data.message;
        greetingCard.dataset.state = "ok";
    } catch (error) {
        greetingResult.textContent =
            `Yêu cầu thất bại: ${error.message}`;
        greetingCard.dataset.state = "error";
    } finally {
        submitButton.disabled = false;
    }
});
