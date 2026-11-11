import time

from fastapi.testclient import TestClient

from backend.app import app


client = TestClient(app)


def test_health_endpoint():
    response = client.get('/api/health')
    assert response.status_code == 200
    assert response.json()['status'] == 'ok'


def test_create_video_job_and_poll_status():
    payload = {
        'title': 'Sunset in Bromo',
        'prompt': 'Create a cinematic video about sunset in Mount Bromo',
        'style': 'Cinematic',
        'duration': '30s',
    }

    create_response = client.post('/api/videos', json=payload)
    assert create_response.status_code == 200, create_response.text
    body = create_response.json()
    assert 'job_id' in body
    assert 'project_id' in body
    assert body['status'] in {'queued', 'initializing', 'processing', 'rendering', 'completed'}
    assert body['generation_mode'] == 'mvp-local-compose'
    assert 'adapter_note' in body

    job_id = body['job_id']
    status_response = client.get(f'/api/videos/{job_id}')
    assert status_response.status_code == 200, status_response.text
    status_body = status_response.json()
    assert status_body['job_id'] == job_id
    assert 'project_id' in status_body
    assert 'status' in status_body
    assert status_body['generation_mode'] == 'mvp-local-compose'


def test_video_file_endpoint_returns_render_file():
    payload = {
        'title': 'Sunset in Bromo',
        'prompt': 'Create a cinematic video about sunset in Mount Bromo',
        'style': 'Cinematic',
        'duration': '30s',
    }
    job = client.post('/api/videos', json=payload).json()

    last_status = None
    for _ in range(80):
        response = client.get(f"/api/videos/{job['job_id']}")
        assert response.status_code == 200, response.text
        last_status = response.json()['status']
        if last_status == 'completed':
            break
        time.sleep(0.5)

    assert last_status == 'completed', f'Job did not complete: {last_status}'

    file_response = client.get(f"/api/videos/{job['job_id']}/file")
    assert file_response.status_code == 200, file_response.text
    assert file_response.headers['content-type'].startswith('video/')
