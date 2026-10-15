from fastapi.testclient import TestClient

from src.app import app, activities

client = TestClient(app)


def test_duplicate_signup_is_rejected():
    original_participants = activities["Chess Club"]["participants"].copy()

    try:
        response = client.post(
            "/activities/Chess Club/signup?email=michael@mergington.edu"
        )

        assert response.status_code == 400
        assert response.json()["detail"] == "Student is already signed up"
    finally:
        activities["Chess Club"]["participants"] = original_participants


def test_activity_full_is_rejected():
    original_activity = activities.get("Test Activity")
    activities["Test Activity"] = {
        "description": "Temporary test activity",
        "schedule": "Fridays, 3:00 PM - 4:00 PM",
        "max_participants": 1,
        "participants": ["alice@example.com"],
    }

    try:
        response = client.post("/activities/Test Activity/signup?email=bob@example.com")

        assert response.status_code == 400
        assert response.json()["detail"] == "Activity is full"
    finally:
        if original_activity is None:
            del activities["Test Activity"]
        else:
            activities["Test Activity"] = original_activity
