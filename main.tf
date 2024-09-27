provider "google" {
  project = var.project
  region  = var.region
}

resource "google_storage_bucket" "airflow_dag_bucket" {
  name     = var.bucket_name
  location = var.region
}

resource "google_compute_instance" "airflow_gce_vm" {
  name         = "airflow-gce-vm"
  machine_type = var.machine_type
  zone         = "${var.region}-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = var.disk_size
    }
  }

  network_interface {
    network = "default"

    access_config {
    }
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y python3-pip python3-venv

    # Create virtual environment
    python3 -m venv airflow_venv
    source airflow_venv/bin/activate

    # Install Airflow and dependencies
    pip install --upgrade pip
    pip install apache-airflow
    pip install apache-airflow-providers-google
    pip install google-cloud-storage

    # Disable example DAGs
    export AIRFLOW__CORE__LOAD_EXAMPLES=False

    # Initialize Airflow database
    airflow db init

    # Create Airflow user
    airflow users create --username admin --password admin --firstname Admin --lastname Admin --role Admin --email ${var.user_email}

    # Get the Airflow dags_folder path
    dags_folder=$(airflow config list | grep dags_folder | awk -F' = ' '{print $2}')

    # Create the dags folder
    mkdir -p "$dags_folder"

    # Create the update_dags.py script in the dags folder
    cat << EOF > "$dags_folder/update_dags.py"
    from airflow import DAG
    from airflow.operators.python_operator import PythonOperator
    from airflow.providers.google.cloud.hooks.gcs import GCSHook
    from datetime import datetime
    import os

    # Function to download DAGs from GCS
    def download_all_dags_from_gcs(bucket_name, gcs_folder, local_dag_folder):
        hook = GCSHook()
        client = hook.get_conn()
        bucket = client.bucket(bucket_name)
        
        # List all objects (files) in the GCS folder
        blobs = bucket.list_blobs(prefix=gcs_folder)
        
        # Filter for .py files and download them to the local folder
        for blob in blobs:
            if blob.name.endswith('.py'):  # Only download .py files
                local_dag_path = os.path.join(local_dag_folder, os.path.basename(blob.name))
                print(f'Downloading {blob.name} to {local_dag_path}')
                with open(local_dag_path, "wb") as f:
                    blob.download_to_file(f)
                print(f'{blob.name} downloaded to {local_dag_path}')

    # Define the DAG that will trigger the download
    default_args = {
       'owner': 'airflow',
       'start_date': datetime(2023, 1, 1),
       'retries': 1,
    }

    with DAG(
       dag_id='gcs_download_dag',
       default_args=default_args,
       schedule_interval=None,
       catchup=False,
    ) as dag:

       # Task to download the DAG
       download_dag_task = PythonOperator(
           task_id='download_dag',
           python_callable=download_all_dags_from_gcs,
           op_kwargs={
                'bucket_name': '${var.bucket_name}',
                'gcs_folder': 'DAGs/',
                'local_dag_folder': "$dags_folder",
            },
       )

       download_dag_task
    EOF

    # Start Airflow webserver and scheduler
    airflow scheduler &
    airflow webserver --port 8080 &
  EOT

  service_account {
    email = google_service_account.airflow_gce_sa.email
    scopes = ["cloud-platform"]
  }

  tags = ["http-server"]
}

resource "google_compute_firewall" "allow_http" {
  name    = "airflow-gce-allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  
}

resource "google_service_account" "airflow_gce_sa" {
  account_id   = "airflow-gce-sa"
  display_name = "Airflow Service Account"
}

resource "google_project_iam_member" "airflow_gce_sa_role" {
  project = var.project
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.airflow_gce_sa.email}"
}
